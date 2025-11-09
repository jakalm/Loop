//
//  SettingsRecommendationManager.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import os.log

class SettingsRecommendationManager {
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    private let settings: () -> LoopSettings
    private let logger = Logger(subsystem: "com.loopkit.Loop", category: "SettingsRecommendationManager")

    // Analysis parameters
    private let minimumMeasurementHours: TimeInterval = 2 * .hours(1)
    private let analysisWindowStride: TimeInterval = 5 * 60 // Check every 5 minutes for continuous periods

    init(glucoseStore: GlucoseStoreProtocol,
         carbStore: CarbStoreProtocol,
         doseStore: DoseStoreProtocol,
         settings: @escaping () -> LoopSettings) {
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.settings = settings
    }

    /// Generate basal rate recommendations based on historical data
    func generateBasalRateRecommendations(daysToAnalyze: Int, completion: @escaping ([BasalRateRecommendation]) -> Void) {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(daysToAnalyze) * .hours(24))

        // Fetch all necessary data
        fetchAnalysisData(from: startDate, to: endDate) { result in
            switch result {
            case .success(let data):
                let (windows, _) = self.identifyValidAnalysisWindows(
                    glucoseSamples: data.glucoseSamples,
                    carbEntries: data.carbEntries,
                    doseEntries: data.doseEntries,
                    from: startDate,
                    to: endDate
                )

                let recommendations = self.generateRecommendations(
                    from: windows,
                    glucoseSamples: data.glucoseSamples,
                    doseEntries: data.doseEntries
                )
                completion(recommendations)

            case .failure(let error):
                self.logger.error("Failed to fetch analysis data: \(String(describing: error))")
                completion([])
            }
        }
    }

    /// Generate debug information about period analysis
    func generateDebugInfo(daysToAnalyze: Int, completion: @escaping (BasalAnalysisDebugInfo) -> Void) {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(daysToAnalyze) * .hours(24))

        // Fetch all necessary data
        fetchAnalysisData(from: startDate, to: endDate) { result in
            switch result {
            case .success(let data):
                let (windows, debugInfo) = self.identifyValidAnalysisWindows(
                    glucoseSamples: data.glucoseSamples,
                    carbEntries: data.carbEntries,
                    doseEntries: data.doseEntries,
                    from: startDate,
                    to: endDate
                )

                completion(debugInfo)

            case .failure(let error):
                self.logger.error("Failed to fetch analysis data: \(String(describing: error))")
                completion(BasalAnalysisDebugInfo(
                    analyzedPeriods: [],
                    totalPeriodsChecked: 0,
                    validPeriodsFound: 0,
                    totalGlucoseSamples: 0,
                    glucoseDateRange: (start: nil, end: nil),
                    analysisPeriod: (start: startDate, end: endDate)
                ))
            }
        }
    }

    private struct AnalysisData {
        let glucoseSamples: [StoredGlucoseSample]
        let carbEntries: [StoredCarbEntry]
        let doseEntries: [DoseEntry]
    }

    private func fetchAnalysisData(from startDate: Date, to endDate: Date, completion: @escaping (Result<AnalysisData>) -> Void) {
        let group = DispatchGroup()
        var glucoseSamples: [StoredGlucoseSample] = []
        var carbEntries: [StoredCarbEntry] = []
        var doseEntries: [DoseEntry] = []
        var errors: [Error] = []

        // Fetch glucose
        group.enter()
        glucoseStore.getGlucoseSamples(start: startDate, end: endDate) { result in
            switch result {
            case .success(let samples):
                glucoseSamples = samples
            case .failure(let error):
                errors.append(error)
            }
            group.leave()
        }

        // Fetch carbs
        group.enter()
        carbStore.getCarbEntries(start: startDate, end: endDate) { result in
            switch result {
            case .success(let entries):
                carbEntries = entries
            case .failure(let error):
                errors.append(error)
            }
            group.leave()
        }

        // Fetch doses
        group.enter()
        doseStore.getNormalizedDoseEntries(start: startDate, end: endDate) { result in
            switch result {
            case .success(let entries):
                doseEntries = entries
            case .failure(let error):
                errors.append(error)
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let error = errors.first {
                completion(.failure(error))
            } else {
                completion(.success(AnalysisData(
                    glucoseSamples: glucoseSamples,
                    carbEntries: carbEntries,
                    doseEntries: doseEntries
                )))
            }
        }
    }

    private func identifyValidAnalysisWindows(
        glucoseSamples: [StoredGlucoseSample],
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        from startDate: Date,
        to endDate: Date
    ) -> ([BasalAnalysisWindow], BasalAnalysisDebugInfo) {
        // Calculate glucose date range for debugging
        let glucoseStart = glucoseSamples.first?.startDate
        let glucoseEnd = glucoseSamples.last?.startDate

        // Find continuous periods that meet all criteria
        let (windows, debugPeriods) = findContinuousValidPeriods(
            glucoseSamples: glucoseSamples,
            carbEntries: carbEntries,
            doseEntries: doseEntries,
            from: startDate,
            to: endDate
        )

        let debugInfo = BasalAnalysisDebugInfo(
            analyzedPeriods: debugPeriods,
            totalPeriodsChecked: debugPeriods.count,
            validPeriodsFound: windows.count,
            totalGlucoseSamples: glucoseSamples.count,
            glucoseDateRange: (start: glucoseStart, end: glucoseEnd),
            analysisPeriod: (start: startDate, end: endDate)
        )

        return (windows, debugInfo)
    }

    private func findContinuousValidPeriods(
        glucoseSamples: [StoredGlucoseSample],
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        from startDate: Date,
        to endDate: Date
    ) -> ([BasalAnalysisWindow], [PeriodAnalysisDebug]) {
        var windows: [BasalAnalysisWindow] = []
        var debugPeriods: [PeriodAnalysisDebug] = []

        // Pre-sort data once for binary search optimizations
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }
        let sortedCarbs = carbEntries.sorted { $0.startDate < $1.startDate }
        let sortedBoluses = doseEntries.filter { $0.type == .bolus }.sorted { $0.startDate < $1.startDate }

        // Pre-compute lookup structures for O(1) checks
        let lowGlucoseThreshold: Double = 72.0  // 4.0 mmol/L
        let lowGlucoseCheckWindow = 8 * .hours(1)

        // Create time-bucketed index for low glucose (bucket by hour for fast range queries)
        var lowGlucoseByHour: [Int: [Date]] = [:]
        for sample in sortedGlucose where sample.quantity.doubleValue(for: .milligramsPerDeciliter) < lowGlucoseThreshold {
            let hourBucket = Int(sample.startDate.timeIntervalSince1970 / 3600)
            lowGlucoseByHour[hourBucket, default: []].append(sample.startDate)
        }

        // Pre-compute carb activity windows
        let maxCarbAbsorptionDuration = 8 * .hours(1)
        let carbActiveWindows: [(start: Date, end: Date)] = sortedCarbs.compactMap { carb in
            guard carb.quantity.doubleValue(for: .gram()) > 1.0 else { return nil }
            return (start: carb.startDate, end: carb.startDate.addingTimeInterval(maxCarbAbsorptionDuration))
        }

        // Track continuous valid periods
        var currentPeriodStart: Date?
        var currentDate = startDate

        // Track periods that were interrupted by recent lows
        // We'll check these later and add back ones with falling trends
        var lowInterruptedPeriods: [(start: Date, end: Date)] = []

        // Cache for glucose index to avoid re-searching
        var glucoseSearchStartIndex = 0
        var carbCheckIndex = 0
        var bolusCheckIndex = 0

        // Check every 5 minutes
        while currentDate < endDate {
            // Quick disqualification checks first (cheapest to most expensive)

            // 1. Check low glucose using bucketed index
            let hasRecentLow = hasLowGlucoseInWindow(
                date: currentDate,
                window: lowGlucoseCheckWindow,
                lowGlucoseByHour: lowGlucoseByHour
            )

            if hasRecentLow {
                if let periodStart = currentPeriodStart {
                    // Save this period as interrupted by low
                    lowInterruptedPeriods.append((start: periodStart, end: currentDate))
                    finalizePeriod(periodStart, currentDate, doseEntries: doseEntries, glucoseSamples: sortedGlucose, &windows, &debugPeriods)
                    currentPeriodStart = nil
                }
                currentDate = currentDate.addingTimeInterval(analysisWindowStride)
                continue
            }

            // 2. Check active carbs using pre-computed windows (optimized with binary search concept)
            var hasActiveCarbs = false
            for window in carbActiveWindows {
                // Since carbs are sorted by start date, we can break early
                if window.start > currentDate {
                    break // All remaining windows start after currentDate
                }
                if currentDate >= window.start && currentDate < window.end {
                    hasActiveCarbs = true
                    break
                }
            }

            if hasActiveCarbs {
                if let periodStart = currentPeriodStart {
                    finalizePeriod(periodStart, currentDate, doseEntries: doseEntries, glucoseSamples: sortedGlucose, &windows, &debugPeriods)
                    currentPeriodStart = nil
                }
                currentDate = currentDate.addingTimeInterval(analysisWindowStride)
                continue
            }

            // 3. Check IOB with cached index
            let iob = calculateActiveInsulinCached(
                sortedBoluses: sortedBoluses,
                at: currentDate,
                cacheIndex: &bolusCheckIndex
            )

            if abs(iob) > 0.5 {
                if let periodStart = currentPeriodStart {
                    finalizePeriod(periodStart, currentDate, doseEntries: doseEntries, glucoseSamples: sortedGlucose, &windows, &debugPeriods)
                    currentPeriodStart = nil
                }
                currentDate = currentDate.addingTimeInterval(analysisWindowStride)
                continue
            }

            // 4. Check glucose (most expensive, do last)
            let glucoseCheck = findNearbyGlucose(
                at: currentDate,
                sortedGlucose: sortedGlucose,
                cacheIndex: &glucoseSearchStartIndex
            )

            guard let glucose = glucoseCheck.glucose, glucoseCheck.inRange else {
                if let periodStart = currentPeriodStart {
                    finalizePeriod(periodStart, currentDate, doseEntries: doseEntries, glucoseSamples: sortedGlucose, &windows, &debugPeriods)
                    currentPeriodStart = nil
                }
                currentDate = currentDate.addingTimeInterval(analysisWindowStride)
                continue
            }

            // Point is valid - continue or start period
            if currentPeriodStart == nil {
                currentPeriodStart = currentDate
            }

            currentDate = currentDate.addingTimeInterval(analysisWindowStride)
        }

        // Finalize any remaining period
        if let periodStart = currentPeriodStart {
            finalizePeriod(periodStart, endDate, doseEntries: doseEntries, glucoseSamples: sortedGlucose, &windows, &debugPeriods)
        }

        // Second pass: Check periods that were interrupted by recent lows
        // If they have falling trends (glucose decreasing), add them back
        // This allows us to reduce basal even after a recent low
        print("🔍 Checking \(lowInterruptedPeriods.count) low-interrupted periods for falling trends")
        for period in lowInterruptedPeriods {
            let duration = period.end.timeIntervalSince(period.start)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            print("  Period: \(formatter.string(from: period.start)) - \(formatter.string(from: period.end)), duration: \(String(format: "%.1f", duration / .hours(1)))h")

            // Only consider periods that meet minimum duration
            guard duration >= minimumMeasurementHours else {
                print("  ⏭️  Too short, skipping")
                continue
            }

            // Check if trend is falling
            let periodGlucose = sortedGlucose.filter { sample in
                sample.startDate >= period.start && sample.startDate <= period.end
            }.sorted { $0.startDate < $1.startDate }

            guard let firstGlucose = periodGlucose.first,
                  let lastGlucose = periodGlucose.last else {
                print("  ⏭️  No glucose data, skipping")
                continue
            }

            let glucoseChange = lastGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) -
                              firstGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)
            let durationHours = duration / .hours(1)
            let trend = durationHours > 0 ? glucoseChange / durationHours : 0

            print("  Trend: \(String(format: "%.1f", trend)) mg/dL/hr")

            // Only add back if falling (negative trend)
            if trend < 0 {
                print("  ✅ Falling trend! Checking linearity...")

                // Check linearity
                let isLinear = isGlucoseTrendLinear(
                    glucoseSamples: sortedGlucose,
                    measurementStart: period.start,
                    measurementEnd: period.end
                )

                if isLinear {
                    print("  ✅ Linear! Adding period back")
                    let activeDoses = collectActiveDoses(
                        doseEntries: doseEntries,
                        measurementStart: period.start,
                        measurementEnd: period.end
                    )
                    windows.append(BasalAnalysisWindow(
                        measurementStart: period.start,
                        measurementEnd: period.end,
                        carbFreeStart: period.start,
                        activeDoses: activeDoses
                    ))
                } else {
                    print("  ❌ Not linear, skipping")
                }
            } else {
                print("  ⏭️  Rising/stable trend, skipping")
            }
        }

        return (windows, debugPeriods)
    }

    private func finalizePeriod(
        _ periodStart: Date,
        _ periodEnd: Date,
        doseEntries: [DoseEntry],
        glucoseSamples: [StoredGlucoseSample],
        _ windows: inout [BasalAnalysisWindow],
        _ debugPeriods: inout [PeriodAnalysisDebug]
    ) {
        let duration = periodEnd.timeIntervalSince(periodStart)

        if duration >= minimumMeasurementHours {
            // Check if glucose trend is linear
            let isLinear = isGlucoseTrendLinear(
                glucoseSamples: glucoseSamples,
                measurementStart: periodStart,
                measurementEnd: periodEnd
            )

            if isLinear {
                // Valid period - add to windows
                let activeDoses = collectActiveDoses(
                    doseEntries: doseEntries,
                    measurementStart: periodStart,
                    measurementEnd: periodEnd
                )
                windows.append(BasalAnalysisWindow(
                    measurementStart: periodStart,
                    measurementEnd: periodEnd,
                    carbFreeStart: periodStart,
                    activeDoses: activeDoses
                ))
                debugPeriods.append(PeriodAnalysisDebug(
                    measurementStart: periodStart,
                    measurementEnd: periodEnd,
                    duration: duration,
                    isValid: true,
                    rejectionReasons: []
                ))
            } else {
                // Non-linear trend - reject
                debugPeriods.append(PeriodAnalysisDebug(
                    measurementStart: periodStart,
                    measurementEnd: periodEnd,
                    duration: duration,
                    isValid: false,
                    rejectionReasons: ["Non-linear glucose trend (peak or valley detected)"]
                ))
            }
        } else if duration > 0 {
            // Too short - add to debug only
            debugPeriods.append(PeriodAnalysisDebug(
                measurementStart: periodStart,
                measurementEnd: periodEnd,
                duration: duration,
                isValid: false,
                rejectionReasons: ["Period too short (\(String(format: "%.1f", duration / .hours(1)))h < 3h)"]
            ))
        }
    }

    private func hasLowGlucoseInWindow(
        date: Date,
        window: TimeInterval,
        lowGlucoseByHour: [Int: [Date]]
    ) -> Bool {
        let checkStart = date.addingTimeInterval(-window)
        let startHourBucket = Int(checkStart.timeIntervalSince1970 / 3600)
        let endHourBucket = Int(date.timeIntervalSince1970 / 3600)

        // Check all hour buckets in the window
        for hourBucket in startHourBucket...endHourBucket {
            if let dates = lowGlucoseByHour[hourBucket] {
                for lowDate in dates where lowDate >= checkStart && lowDate < date {
                    return true
                }
            }
        }
        return false
    }

    private func findNearbyGlucose(
        at date: Date,
        sortedGlucose: [StoredGlucoseSample],
        cacheIndex: inout Int
    ) -> (glucose: StoredGlucoseSample?, inRange: Bool) {
        let glucoseWindow: TimeInterval = 10 * 60
        var closestGlucose: StoredGlucoseSample?
        var closestDistance = Double.infinity

        // Search forward from cached index
        let startIndex = max(0, cacheIndex - 5) // Look back a bit in case we skipped
        for i in startIndex..<sortedGlucose.count {
            let sample = sortedGlucose[i]
            let distance = abs(sample.startDate.timeIntervalSince(date))

            // If we've gone too far past our window, stop searching
            if sample.startDate > date && distance > glucoseWindow {
                break
            }

            if distance <= glucoseWindow && distance < closestDistance {
                closestGlucose = sample
                closestDistance = distance
                cacheIndex = i
            }
        }

        guard let glucose = closestGlucose else {
            return (nil, false)
        }

        // Check if in range
        let glucoseValue = glucose.quantity.doubleValue(for: .milligramsPerDeciliter)
        let lowerThreshold: Double = 72.0  // 4.0 mmol/L
        let upperThreshold: Double = 234.0 // 13.0 mmol/L
        let inRange = glucoseValue >= lowerThreshold && glucoseValue <= upperThreshold

        return (glucose, inRange)
    }

    private func calculateActiveInsulinCached(
        sortedBoluses: [DoseEntry],
        at date: Date,
        cacheIndex: inout Int
    ) -> Double {
        let insulinActionDuration: TimeInterval = 6 * .hours(1)
        let earliestRelevantTime = date.addingTimeInterval(-insulinActionDuration)
        var totalIOB: Double = 0

        // Start from cached index (or beginning if cache is invalid)
        let startIndex = max(0, cacheIndex)

        for i in startIndex..<sortedBoluses.count {
            let dose = sortedBoluses[i]

            // Stop if we've passed the current date
            if dose.startDate >= date {
                break
            }

            // Skip if too old to be active
            if dose.startDate < earliestRelevantTime {
                cacheIndex = i + 1 // Update cache to skip old boluses next time
                continue
            }

            let timeSinceDose = date.timeIntervalSince(dose.startDate)
            let percentRemaining = max(0, 1 - (timeSinceDose / insulinActionDuration))
            let activeInsulin = dose.programmedUnits * percentRemaining
            totalIOB += activeInsulin
        }

        return totalIOB
    }

    private func checkPointValidity(
        at date: Date,
        carbEntries: [StoredCarbEntry],
        glucoseSamples: [StoredGlucoseSample],
        doseEntries: [DoseEntry]
    ) -> [String] {
        var reasons: [String] = []

        // Check for recent low blood glucose (within 8 hours before this point)
        // This is a safety check to avoid recommending higher basals after lows
        let lowGlucoseCheckWindow = 8 * .hours(1)
        let lowGlucoseThreshold: Double = 72.0  // 4.0 mmol/L
        let lowCheckStart = date.addingTimeInterval(-lowGlucoseCheckWindow)

        let recentLows = glucoseSamples.filter { sample in
            sample.startDate >= lowCheckStart &&
            sample.startDate < date &&
            sample.quantity.doubleValue(for: .milligramsPerDeciliter) < lowGlucoseThreshold
        }

        if !recentLows.isEmpty {
            reasons.append("Recent low glucose (< 4.0 mmol/L) within 8 hours")
            return reasons
        }

        // Check for active carbs at this point (>1g still absorbing)
        // Use a conservative 8-hour absorption window
        let maxCarbAbsorptionDuration = 8 * .hours(1)

        let activeCarbsAtPoint = carbEntries.filter { carb in
            // Carb must be entered before this point
            guard carb.startDate <= date else { return false }

            // Check if carb is still absorbing at this time point
            let carbEndTime = carb.startDate.addingTimeInterval(maxCarbAbsorptionDuration)
            guard carbEndTime > date else { return false }

            // Only care if more than 1g
            return carb.quantity.doubleValue(for: .gram()) > 1.0
        }

        if !activeCarbsAtPoint.isEmpty {
            reasons.append("Active carbs (>1g)")
            return reasons
        }

        // Check for high active insulin (IOB from boluses)
        // Only check boluses - exclude basal/temp basal since we want to analyze those
        let insulinActionDuration: TimeInterval = 6 * .hours(1)
        let iob = calculateActiveInsulin(
            doseEntries: doseEntries,
            at: date,
            insulinActionDuration: insulinActionDuration
        )

        // If absolute IOB > 0.5 U, skip this point
        // This includes both positive (excess insulin) and negative (insulin deficit from suspensions)
        if abs(iob) > 0.5 {
            reasons.append("High active insulin")
            return reasons
        }

        // Check for glucose reading near this time point (within 10 minutes)
        let glucoseWindow: TimeInterval = 10 * 60
        let nearbyGlucose = glucoseSamples.filter { sample in
            abs(sample.startDate.timeIntervalSince(date)) <= glucoseWindow
        }.sorted { abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date)) }

        guard let closestGlucose = nearbyGlucose.first else {
            reasons.append("No glucose data")
            return reasons
        }

        // Check if glucose is in range
        let glucoseValue = closestGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)
        let lowerThreshold: Double = 72.0  // 4.0 mmol/L
        let upperThreshold: Double = 234.0 // 13.0 mmol/L

        if glucoseValue < lowerThreshold || glucoseValue > upperThreshold {
            reasons.append("Glucose out of range")
            return reasons
        }

        return reasons
    }

    /// Calculate active insulin on board (IOB) from boluses only at a specific time
    /// Uses exponential insulin absorption model
    private func calculateActiveInsulin(
        doseEntries: [DoseEntry],
        at date: Date,
        insulinActionDuration: TimeInterval
    ) -> Double {
        var totalIOB: Double = 0

        // Only consider boluses that could still be active
        let relevantDoses = doseEntries.filter { dose in
            dose.type == .bolus &&
            dose.startDate < date &&
            date.timeIntervalSince(dose.startDate) < insulinActionDuration
        }

        for dose in relevantDoses {
            let timeSinceDose = date.timeIntervalSince(dose.startDate)

            // Use exponential decay model (simplified)
            // Assumes most insulin is absorbed in first 3 hours, tails off to 6 hours
            let percentRemaining = max(0, 1.0 - (timeSinceDose / insulinActionDuration))
            let iob = dose.programmedUnits * percentRemaining

            totalIOB += iob
        }

        return totalIOB
    }

    private func collectActiveDoses(
        doseEntries: [DoseEntry],
        measurementStart: Date,
        measurementEnd: Date
    ) -> [DoseEntry] {
        let insulinActionDuration: TimeInterval = 6 * .hours(1)

        return doseEntries.filter { dose in
            let doseEnd = dose.endDate
            let doseStart = dose.startDate

            switch dose.type {
            case .bolus:
                let bolusEndImpact = doseStart.addingTimeInterval(insulinActionDuration)
                return bolusEndImpact > measurementStart && doseStart < measurementEnd
            case .tempBasal, .resume, .suspend:
                return doseStart < measurementEnd && doseEnd > measurementStart
            case .basal:
                return false
            }
        }
    }

    private func createAnalysisWindowWithDebug(
        carbFreeStart: Date,
        measurementStart: Date,
        measurementEnd: Date,
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        glucoseSamples: [StoredGlucoseSample]
    ) -> (BasalAnalysisWindow?, [String]) {
        var rejectionReasons: [String] = []

        return (createAnalysisWindow(
            carbFreeStart: carbFreeStart,
            measurementStart: measurementStart,
            measurementEnd: measurementEnd,
            carbEntries: carbEntries,
            doseEntries: doseEntries,
            glucoseSamples: glucoseSamples,
            rejectionReasons: &rejectionReasons
        ), rejectionReasons)
    }

    private func createAnalysisWindow(
        carbFreeStart: Date,
        measurementStart: Date,
        measurementEnd: Date,
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        glucoseSamples: [StoredGlucoseSample],
        rejectionReasons: inout [String]
    ) -> BasalAnalysisWindow? {
        // Check for carbs during the measurement period only
        let carbsInPeriod = carbEntries.filter { carb in
            let carbStart = carb.startDate
            // Check if carb would still be active during the measurement window
            // Assuming max absorption of 8 hours
            let carbEndImpact = carbStart.addingTimeInterval(.hours(8))
            return carbEndImpact > measurementStart && carbStart < measurementEnd
        }

        if !carbsInPeriod.isEmpty {
            rejectionReasons.append("Active carbs in period")
            return nil
        }

        // Check for sufficient glucose data
        let glucoseInWindow = glucoseSamples.filter { sample in
            sample.startDate >= measurementStart && sample.startDate <= measurementEnd
        }

        // Need at least 4 readings (one every 30 min for 2 hours)
        if glucoseInWindow.count < 4 {
            rejectionReasons.append("Insufficient glucose readings (\(glucoseInWindow.count) < 4)")
            return nil
        }

        // Check that glucose was within 4.0-11.0 mmol/L (72-198 mg/dL) for at least 2 hours
        if !isGlucoseInRangeForMinimumDuration(
            glucoseSamples: glucoseInWindow,
            measurementStart: measurementStart,
            measurementEnd: measurementEnd,
            minimumDuration: 2 * .hours(1)
        ) {
            rejectionReasons.append("Glucose not in range (4.0-11.0 mmol/L) for 2+ hours")
            return nil
        }

        // Collect doses that affect this period for insulin correction
        // Insulin remains active for ~6 hours after a bolus
        let insulinActionDuration: TimeInterval = 6 * .hours(1)

        let activeDoses = doseEntries.filter { dose in
            let doseEnd = dose.endDate
            let doseStart = dose.startDate

            switch dose.type {
            case .bolus:
                // Check if bolus would still be active during measurement period
                let bolusEndImpact = doseStart.addingTimeInterval(insulinActionDuration)
                return bolusEndImpact > measurementStart && doseStart < measurementEnd
            case .tempBasal, .resume, .suspend:
                // Check if these overlap with measurement period
                return doseStart < measurementEnd && doseEnd > measurementStart
            case .basal:
                return false
            }
        }

        return BasalAnalysisWindow(
            measurementStart: measurementStart,
            measurementEnd: measurementEnd,
            carbFreeStart: carbFreeStart,
            activeDoses: activeDoses
        )
    }

    /// Check if glucose was within the target range (4.0-11.0 mmol/L) for at least the specified duration
    private func isGlucoseInRangeForMinimumDuration(
        glucoseSamples: [StoredGlucoseSample],
        measurementStart: Date,
        measurementEnd: Date,
        minimumDuration: TimeInterval
    ) -> Bool {
        // Thresholds for acceptable glucose range
        let lowerThreshold: Double = 72.0  // 4.0 mmol/L in mg/dL
        let upperThreshold: Double = 198.0 // 11.0 mmol/L in mg/dL

        // Sort samples by date
        let sortedSamples = glucoseSamples.sorted { $0.startDate < $1.startDate }

        guard let firstSample = sortedSamples.first else {
            return false
        }

        // Track the longest continuous period within range
        var longestInRangeDuration: TimeInterval = 0
        var currentInRangeStart: Date? = nil

        for sample in sortedSamples {
            let glucoseValue = sample.quantity.doubleValue(for: .milligramsPerDeciliter)

            // Check if glucose is within range
            if glucoseValue >= lowerThreshold && glucoseValue <= upperThreshold {
                // Start tracking if not already
                if currentInRangeStart == nil {
                    currentInRangeStart = sample.startDate
                }
            } else {
                // Out of range - check if we had a valid period
                if let inRangeStart = currentInRangeStart {
                    let duration = sample.startDate.timeIntervalSince(inRangeStart)
                    longestInRangeDuration = max(longestInRangeDuration, duration)
                    currentInRangeStart = nil
                }
            }
        }

        // Check final period if we ended in range
        if let inRangeStart = currentInRangeStart {
            let duration = measurementEnd.timeIntervalSince(inRangeStart)
            longestInRangeDuration = max(longestInRangeDuration, duration)
        }

        return longestInRangeDuration >= minimumDuration
    }

    private func generateRecommendations(
        from windows: [BasalAnalysisWindow],
        glucoseSamples: [StoredGlucoseSample],
        doseEntries: [DoseEntry]
    ) -> [BasalRateRecommendation] {
        let calendar = Calendar.current
        let referenceDate = Date()
        let dayStart = calendar.startOfDay(for: referenceDate)

        guard !windows.isEmpty else {
            // No data at all - return insufficient data for entire day
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
            return [createInsufficientDataRecommendation(from: dayStart, to: dayEnd)]
        }

        // Normalize all window times to the same reference day (by time of day only)
        // This way we can group windows from different days by their time of day
        func normalizeToReferenceDay(_ date: Date) -> Date {
            let components = calendar.dateComponents([.hour, .minute, .second], from: date)
            return calendar.date(bySettingHour: components.hour ?? 0,
                                minute: components.minute ?? 0,
                                second: components.second ?? 0,
                                of: dayStart) ?? date
        }

        // Collect all unique time-of-day boundaries from window starts and ends
        // Track which boundaries are window ends (to keep them as-is) vs window starts (subtract 1 min)
        var boundaries = Set<Date>()
        var windowEnds = Set<Date>()

        boundaries.insert(dayStart) // 00:00

        for window in windows {
            boundaries.insert(normalizeToReferenceDay(window.measurementStart))
            let normalizedEnd = normalizeToReferenceDay(window.measurementEnd)
            boundaries.insert(normalizedEnd)
            windowEnds.insert(normalizedEnd)
        }

        // Sort boundaries by time of day
        var sortedBoundaries = boundaries.sorted()

        // Add end of day if not already present
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
        if sortedBoundaries.last != dayEnd {
            sortedBoundaries.append(dayEnd)
        }

        var recommendations: [BasalRateRecommendation] = []

        // Create a segment for each pair of consecutive boundaries
        for i in 0..<(sortedBoundaries.count - 1) {
            let currentBoundary = sortedBoundaries[i]
            let nextBoundary = sortedBoundaries[i + 1]

            // Determine segment start time:
            // - If current boundary is a window end, start 1 minute after (e.g., 09:04, 10:39)
            // - Otherwise, use boundary as-is (e.g., 00:00, 02:58, 04:43)
            let segmentStart: Date
            if windowEnds.contains(currentBoundary) && currentBoundary != dayStart {
                segmentStart = calendar.date(byAdding: .minute, value: 1, to: currentBoundary) ?? currentBoundary
            } else {
                segmentStart = currentBoundary
            }

            // Determine segment end time:
            // - If next boundary is a window end, keep it as-is (e.g., 09:03, 10:38)
            // - Otherwise, subtract 1 minute (e.g., 02:57, 04:42, 23:59)
            let segmentEnd: Date
            if windowEnds.contains(nextBoundary) {
                segmentEnd = nextBoundary
            } else {
                segmentEnd = calendar.date(byAdding: .minute, value: -1, to: nextBoundary) ?? nextBoundary
            }

            // Find all windows that overlap this segment (by time of day)
            // A window overlaps if it fully contains the segment
            let overlappingWindows = windows.filter { window in
                let normalizedWindowStart = normalizeToReferenceDay(window.measurementStart)
                let normalizedWindowEnd = normalizeToReferenceDay(window.measurementEnd)
                // Window must start at or before segment start, and end at or after segment end
                return normalizedWindowStart <= segmentStart && normalizedWindowEnd >= segmentEnd
            }

            // If no overlapping windows, this is a gap - create insufficient data recommendation
            if overlappingWindows.isEmpty {
                let insufficientRec = createInsufficientDataRecommendation(from: segmentStart, to: segmentEnd)
                recommendations.append(insufficientRec)
                continue
            }

            // Deduplicate windows based on measurementStart and measurementEnd to ensure
            // each qualifying period is only counted once in the calculations
            let uniqueWindows = overlappingWindows.reduce(into: [BasalAnalysisWindow]()) { result, window in
                let isDuplicate = result.contains { existing in
                    existing.measurementStart == window.measurementStart &&
                    existing.measurementEnd == window.measurementEnd
                }
                if !isDuplicate {
                    result.append(window)
                }
            }

            var totalAbsorbedInsulin: Double = 0
            var totalGlucoseChange: Double = 0
            var totalDurationHours: Double = 0
            var validWindowCount = 0
            var startGlucoseValues: [HKQuantity] = []
            var endGlucoseValues: [HKQuantity] = []

            for window in uniqueWindows {
                let windowGlucose = glucoseSamples.filter { sample in
                    sample.startDate >= window.measurementStart && sample.startDate <= window.measurementEnd
                }.sorted { $0.startDate < $1.startDate }

                guard let firstGlucose = windowGlucose.first,
                      let lastGlucose = windowGlucose.last else { continue }

                // Calculate observed glucose change
                let observedGlucoseChange = lastGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) -
                                  firstGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)

                // Calculate total insulin absorbed during this window
                // This includes basal, temp basal, and any bolus absorption
                let absorbedInsulin = calculateAbsorbedInsulin(
                    doseEntries: doseEntries,
                    periodStart: window.measurementStart,
                    periodEnd: window.measurementEnd
                )

                let durationHours = window.duration / .hours(1)

                totalAbsorbedInsulin += absorbedInsulin
                totalGlucoseChange += observedGlucoseChange
                totalDurationHours += durationHours
                validWindowCount += 1
                startGlucoseValues.append(firstGlucose.quantity)
                endGlucoseValues.append(lastGlucose.quantity)
            }

            // Get current basal rate setting for this segment
            let currentBasal = settings().basalRateSchedule?.value(at: segmentStart) ?? 0.0

            // Calculate average insulin per hour and glucose change per hour
            let avgAbsorbedInsulinPerHour = totalDurationHours > 0 ? totalAbsorbedInsulin / totalDurationHours : 0
            let avgGlucoseChangePerHour = totalDurationHours > 0 ? totalGlucoseChange / totalDurationHours : 0

            print("🔍 Basal calculation for segment \(segmentStart):")
            print("   Absorbed insulin: \(String(format: "%.2f", avgAbsorbedInsulinPerHour)) U/hr")
            print("   Glucose change: \(String(format: "%.2f", avgGlucoseChangePerHour)) mg/dL/hr")
            print("   Current basal: \(String(format: "%.2f", currentBasal)) U/hr")

            // Calculate the recommended basal based on absorbed insulin and glucose trend
            // The logic:
            // - The absorbed insulin rate represents what was actually delivered during the qualifying period
            // - If glucose was stable, that absorption rate was appropriate
            // - If glucose was falling, we had too much insulin → recommend less
            // - If glucose was rising, we had too little insulin → recommend more
            //
            // Use ISF (Insulin Sensitivity Factor) to calculate the adjustment:
            // - If glucose is falling at X mmol/L/hr and ISF = Y mmol/L/U
            // - Then we have (X / Y) U/hr excess insulin
            // - Recommended basal = absorbed insulin - (X / Y)

            // Get ISF from settings (use value at segment start time)
            let isfSchedule = settings().insulinSensitivitySchedule
            let isfValue = isfSchedule?.quantity(at: segmentStart) ?? HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 50.0)
            let isfInMmolPerU = isfValue.doubleValue(for: .millimolesPerLiter)

            print("   ISF: \(String(format: "%.1f", isfInMmolPerU)) mmol/L/U")

            // Convert glucose change to mmol/L/hr
            let avgGlucoseChangeInMmol = avgGlucoseChangePerHour / 18.0

            // Calculate insulin adjustment needed
            // If falling: glucose change is negative, so insulinAdjustment is negative (reduce basal)
            // If rising: glucose change is positive, so insulinAdjustment is positive (increase basal)
            let insulinAdjustment = avgGlucoseChangeInMmol / isfInMmolPerU
            let rawRecommendedBasal = avgAbsorbedInsulinPerHour + insulinAdjustment

            print("   Glucose change: \(String(format: "%.2f", avgGlucoseChangeInMmol)) mmol/L/hr")
            print("   Insulin adjustment: \(String(format: "%.3f", insulinAdjustment)) U/hr")
            print("   Raw recommended: \(String(format: "%.2f", rawRecommendedBasal)) U/hr")

            // If change is less than half the minimum step (0.025 U/hr), keep current basal
            let recommendedBasal: Double
            if abs(rawRecommendedBasal - currentBasal) < 0.025 {
                print("   Difference < 0.025, keeping current basal")
                recommendedBasal = currentBasal
            } else {
                // Floor to 0.05 U/hr step (always round down for safety)
                recommendedBasal = max(0, floor(rawRecommendedBasal / 0.05) * 0.05)
                print("   Recommended (floored): \(String(format: "%.2f", recommendedBasal)) U/hr")
            }

            // Calculate average trend for display
            let averageTrend = avgGlucoseChangePerHour

            // Calculate confidence based on sample count and trend consistency
            let confidence = min(1.0, Double(validWindowCount) / 10.0)

            let avgStart: HKQuantity
            let avgEnd: HKQuantity

            if !startGlucoseValues.isEmpty {
                let avgStartGlucose = startGlucoseValues.reduce(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)) { result, quantity in
                    HKQuantity(unit: .milligramsPerDeciliter,
                              doubleValue: result.doubleValue(for: .milligramsPerDeciliter) + quantity.doubleValue(for: .milligramsPerDeciliter))
                }
                avgStart = HKQuantity(unit: .milligramsPerDeciliter,
                                         doubleValue: avgStartGlucose.doubleValue(for: .milligramsPerDeciliter) / Double(startGlucoseValues.count))

                let avgEndGlucose = endGlucoseValues.reduce(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)) { result, quantity in
                    HKQuantity(unit: .milligramsPerDeciliter,
                              doubleValue: result.doubleValue(for: .milligramsPerDeciliter) + quantity.doubleValue(for: .milligramsPerDeciliter))
                }
                avgEnd = HKQuantity(unit: .milligramsPerDeciliter,
                                       doubleValue: avgEndGlucose.doubleValue(for: .milligramsPerDeciliter) / Double(endGlucoseValues.count))
            } else {
                avgStart = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)
                avgEnd = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)
            }

            let calendar = Calendar.current
            let hourOfDay = calendar.component(.hour, from: segmentStart)

            let recommendation = BasalRateRecommendation(
                startDate: segmentStart,
                endDate: segmentEnd,
                hourOfDay: hourOfDay,
                currentBasalRate: currentBasal,
                recommendedBasalRate: recommendedBasal,
                glucoseTrend: averageTrend,
                startGlucose: avgStart,
                endGlucose: avgEnd,
                confidence: confidence,
                sampleCount: validWindowCount,
                qualifyingWindows: uniqueWindows
            )

            recommendations.append(recommendation)
        }

        // Merge consecutive segments with the same recommended basal rate
        return mergeConsecutiveRecommendations(recommendations)
    }

    /// Creates an "Insufficient Data" recommendation for a time period
    private func createInsufficientDataRecommendation(from startDate: Date, to endDate: Date) -> BasalRateRecommendation {
        let calendar = Calendar.current
        let hourOfDay = calendar.component(.hour, from: startDate)
        let currentBasal = settings().basalRateSchedule?.value(at: startDate) ?? 0.0

        return BasalRateRecommendation(
            startDate: startDate,
            endDate: endDate,
            hourOfDay: hourOfDay,
            currentBasalRate: currentBasal,
            recommendedBasalRate: currentBasal,
            glucoseTrend: 0,
            startGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0),
            endGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0),
            confidence: 0,
            sampleCount: 0,
            qualifyingWindows: []
        )
    }

    /// Merges consecutive hourly recommendations that have the same recommended basal rate
    private func mergeConsecutiveRecommendations(_ hourlyRecs: [BasalRateRecommendation]) -> [BasalRateRecommendation] {
        guard !hourlyRecs.isEmpty else { return [] }

        var merged: [BasalRateRecommendation] = []
        var currentGroup: [BasalRateRecommendation] = [hourlyRecs[0]]

        for i in 1..<hourlyRecs.count {
            let prev = hourlyRecs[i - 1]
            let current = hourlyRecs[i]

            // Check if this segment should be merged with the previous group
            // Only merge if:
            // 1. Both have data (sampleCount > 0) OR both have no data (sampleCount == 0)
            // 2. Recommended basal rates are the same (within 0.001 tolerance)
            let bothHaveData = prev.sampleCount > 0 && current.sampleCount > 0
            let bothNoData = prev.sampleCount == 0 && current.sampleCount == 0
            let sameBasalRate = abs(current.recommendedBasalRate - prev.recommendedBasalRate) < 0.001

            if (bothHaveData || bothNoData) && sameBasalRate {
                currentGroup.append(current)
            } else {
                // Different category or basal rate - finalize current group and start new one
                if let mergedRec = createMergedRecommendation(from: currentGroup) {
                    merged.append(mergedRec)
                }
                currentGroup = [current]
            }
        }

        // Don't forget the last group
        if let mergedRec = createMergedRecommendation(from: currentGroup) {
            merged.append(mergedRec)
        }

        return merged
    }

    /// Creates a single recommendation from a group of consecutive hourly recommendations
    private func createMergedRecommendation(from group: [BasalRateRecommendation]) -> BasalRateRecommendation? {
        guard let first = group.first, let last = group.last else { return nil }

        // Use the start of the first hour and end of the last hour
        let startDate = first.startDate
        let endDate = last.endDate
        let hourOfDay = first.hourOfDay

        // Aggregate statistics from all hours in the group
        let totalSampleCount = group.reduce(0) { $0 + $1.sampleCount }

        // Deduplicate windows based on measurementStart and measurementEnd
        let allWindows = group.flatMap { $0.qualifyingWindows }
        let uniqueWindows = allWindows.reduce(into: [BasalAnalysisWindow]()) { result, window in
            let isDuplicate = result.contains { existing in
                existing.measurementStart == window.measurementStart &&
                existing.measurementEnd == window.measurementEnd
            }
            if !isDuplicate {
                result.append(window)
            }
        }

        // Weight averages by sample count
        var weightedTrend: Double = 0
        var weightedStartGlucose: Double = 0
        var weightedEndGlucose: Double = 0
        var weightedConfidence: Double = 0
        var weightedCurrentBasal: Double = 0

        for rec in group {
            let weight = Double(rec.sampleCount)
            weightedTrend += rec.glucoseTrend * weight
            weightedStartGlucose += rec.startGlucose.doubleValue(for: .milligramsPerDeciliter) * weight
            weightedEndGlucose += rec.endGlucose.doubleValue(for: .milligramsPerDeciliter) * weight
            weightedConfidence += rec.confidence * weight
            weightedCurrentBasal += rec.currentBasalRate * weight
        }

        let totalWeight = Double(totalSampleCount)
        let avgTrend = totalWeight > 0 ? weightedTrend / totalWeight : 0
        let avgStartGlucose = totalWeight > 0 ? weightedStartGlucose / totalWeight : 0
        let avgEndGlucose = totalWeight > 0 ? weightedEndGlucose / totalWeight : 0
        let avgConfidence = totalWeight > 0 ? weightedConfidence / totalWeight : 0
        let avgCurrentBasal = totalWeight > 0 ? weightedCurrentBasal / totalWeight : first.currentBasalRate

        // Use the recommended basal from the first (they're all the same in the group)
        let recommendedBasal = first.recommendedBasalRate

        return BasalRateRecommendation(
            startDate: startDate,
            endDate: endDate,
            hourOfDay: hourOfDay,
            currentBasalRate: avgCurrentBasal,
            recommendedBasalRate: recommendedBasal,
            glucoseTrend: avgTrend,
            startGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgStartGlucose),
            endGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgEndGlucose),
            confidence: avgConfidence,
            sampleCount: uniqueWindows.count,  // Use deduplicated count
            qualifyingWindows: uniqueWindows
        )
    }

    /// Performs simple linear regression on glucose values over time
    /// Returns (slope, intercept) or nil if calculation fails
    private func linearRegression(times: [TimeInterval], values: [Double]) -> (slope: Double, intercept: Double)? {
        guard times.count == values.count, times.count >= 2 else { return nil }

        let n = Double(times.count)
        let sumX = times.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(times, values).map(*).reduce(0, +)
        let sumXX = times.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 0.0001 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return (slope, intercept)
    }

    /// Checks if glucose data shows a linear trend (no significant peaks or valleys in the middle)
    /// Returns true if the trend is sufficiently linear
    private func isGlucoseTrendLinear(
        glucoseSamples: [StoredGlucoseSample],
        measurementStart: Date,
        measurementEnd: Date
    ) -> Bool {
        // Get glucose samples within the measurement period
        let samples = glucoseSamples.filter { sample in
            sample.startDate >= measurementStart && sample.startDate <= measurementEnd
        }.sorted { $0.startDate < $1.startDate }

        guard samples.count >= 4 else {
            // Not enough points to assess linearity - accept it
            print("⚪️ Linearity check: Not enough samples (\(samples.count)) - accepting")
            return true
        }

        // Convert to time offsets and glucose values
        let startTime = samples[0].startDate.timeIntervalSince1970
        let times = samples.map { $0.startDate.timeIntervalSince1970 - startTime }
        let values = samples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        print("📊 Linearity check for \(formatter.string(from: measurementStart)) - \(formatter.string(from: measurementEnd))")
        print("   Glucose values: \(values.map { String(format: "%.0f", $0) }.joined(separator: ", "))")

        // Perform linear regression
        guard let (slope, intercept) = linearRegression(times: times, values: values) else {
            print("⚪️ Linear regression failed - accepting")
            return true // Can't determine - accept it
        }

        print("   Slope: \(String(format: "%.2f", slope * 3600)) mg/dL/hr")

        // Calculate residuals (actual - predicted)
        let residuals = zip(times, values).map { time, value in
            let predicted = slope * time + intercept
            return value - predicted
        }

        // Skip first and last points (edges are less reliable)
        let middleResiduals = Array(residuals.dropFirst().dropLast())
        guard middleResiduals.count >= 2 else {
            print("⚪️ Not enough middle residuals - accepting")
            return true
        }

        // Calculate standard deviation of residuals
        let meanResidual = middleResiduals.reduce(0, +) / Double(middleResiduals.count)
        let variance = middleResiduals.map { pow($0 - meanResidual, 2) }.reduce(0, +) / Double(middleResiduals.count)
        let stdDev = sqrt(variance)

        guard stdDev > 0 else {
            print("⚪️ StdDev is zero - accepting")
            return true
        }

        print("   Residuals: \(middleResiduals.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
        print("   StdDev: \(String(format: "%.1f", stdDev))")

        // Better approach: Detect U-shapes and ∩-shapes by looking at residual trends
        // Split residuals into three sections: beginning, middle, end
        let n = middleResiduals.count
        let section1End = n / 3
        let section2End = 2 * n / 3

        let section1 = Array(middleResiduals[0..<section1End])
        let section2 = Array(middleResiduals[section1End..<section2End])
        let section3 = Array(middleResiduals[section2End..<n])

        let avg1 = section1.isEmpty ? 0 : section1.reduce(0, +) / Double(section1.count)
        let avg2 = section2.isEmpty ? 0 : section2.reduce(0, +) / Double(section2.count)
        let avg3 = section3.isEmpty ? 0 : section3.reduce(0, +) / Double(section3.count)

        print("   Section averages: [\(String(format: "%.1f", avg1)), \(String(format: "%.1f", avg2)), \(String(format: "%.1f", avg3))]")

        // Detect U-shape or n-shape (inverted U): Look for systematic pattern where
        // the middle section is opposite in sign to the edges

        // Key requirements:
        // 1. Both edges must have the same sign (both pos or both neg)
        // 2. Middle must be opposite sign
        // 3. Middle must be substantially larger in magnitude (not just noise)

        let edgesNegative = avg1 < 0 && avg3 < 0
        let edgesPositive = avg1 > 0 && avg3 > 0
        let edgesSameSign = edgesNegative || edgesPositive

        // For a true curvature pattern, the middle should be substantial (not just noise)
        // Use absolute threshold: at least 0.5 * stdDev AND at least 5 mg/dL
        let minMagnitude = max(0.5 * stdDev, 5.0)

        let middleOpposite = (edgesNegative && avg2 > minMagnitude) || (edgesPositive && avg2 < -minMagnitude)

        // Middle must be significantly more extreme than edges
        let edgeAvg = (abs(avg1) + abs(avg3)) / 2.0

        // Require middle to be both:
        // - At least 1.5x the average of edges (relative check)
        // - At least 8 mg/dL different from edge average (absolute check)
        let relativeDiff = abs(avg2) > 1.5 * edgeAvg
        let absoluteDiff = abs(avg2) - edgeAvg > 8.0
        let middleSignificantlyDifferent = relativeDiff && absoluteDiff

        let hasCurvature = edgesSameSign && middleOpposite && middleSignificantlyDifferent

        print("   Edges same sign: \(edgesSameSign), middle opposite: \(middleOpposite), middle significantly different: \(middleSignificantlyDifferent)")
        print("   Has curvature: \(hasCurvature)")

        if hasCurvature {
            print("❌ Rejected: Non-linear curve detected (n-shape or U-shape)")
            return false
        }

        print("✅ Accepted: Linear trend")
        return true
    }

    /// Calculate the average scheduled basal rate that was actually delivered during a period
    /// This uses .basal type dose entries to determine what the scheduled basal rate was
    /// Returns the average basal rate in U/hr, or nil if no basal data available
    private func calculateAverageScheduledBasalRate(
        doseEntries: [DoseEntry],
        start: Date,
        end: Date
    ) -> Double? {
        // Filter for .basal doses that overlap with this period
        let basalDoses = doseEntries.filter { dose in
            dose.type == .basal &&
            dose.startDate < end &&
            dose.endDate > start
        }

        guard !basalDoses.isEmpty else {
            return nil
        }

        // Calculate weighted average based on duration of each basal segment
        var totalInsulin: Double = 0
        var totalDuration: TimeInterval = 0

        for dose in basalDoses {
            // Calculate overlap between dose and measurement period
            let overlapStart = max(dose.startDate, start)
            let overlapEnd = min(dose.endDate, end)
            let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)

            if overlapDuration > 0 {
                let insulinDelivered = dose.unitsPerHour * (overlapDuration / .hours(1))
                totalInsulin += insulinDelivered
                totalDuration += overlapDuration
            }
        }

        guard totalDuration > 0 else {
            return nil
        }

        // Calculate average rate
        return totalInsulin / (totalDuration / .hours(1))
    }

    /// Calculate the total insulin absorbed during a measurement period
    /// This includes basal, temp basal, and any bolus insulin that was absorbed during the period
    /// Uses insulin absorption model to account for insulin given before the period
    private func calculateAbsorbedInsulin(
        doseEntries: [DoseEntry],
        periodStart: Date,
        periodEnd: Date
    ) -> Double {
        let insulinActionDuration: TimeInterval = 6 * .hours(1)
        var totalAbsorbed: Double = 0

        // Look back to include any insulin doses that could still be absorbing during the period
        let lookbackStart = periodStart.addingTimeInterval(-insulinActionDuration)

        let relevantDoses = doseEntries.filter { dose in
            dose.endDate > lookbackStart && dose.startDate < periodEnd
        }

        for dose in relevantDoses {
            switch dose.type {
            case .bolus:
                // Calculate how much of the bolus was absorbed during the period
                let bolusAbsorbed = calculateBolusAbsorption(
                    bolusAmount: dose.programmedUnits,
                    bolusTime: dose.startDate,
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    insulinActionDuration: insulinActionDuration
                )
                totalAbsorbed += bolusAbsorbed

            case .basal, .tempBasal:
                // Calculate basal/temp basal delivered during the period
                let overlapStart = max(dose.startDate, periodStart)
                let overlapEnd = min(dose.endDate, periodEnd)

                if overlapStart < overlapEnd {
                    let overlapDuration = overlapEnd.timeIntervalSince(overlapStart) / .hours(1)
                    let insulinDelivered = dose.unitsPerHour * overlapDuration
                    totalAbsorbed += insulinDelivered
                }

            case .suspend:
                // No insulin during suspension
                break

            case .resume:
                // Resume is just a marker, no insulin
                break
            }
        }

        return totalAbsorbed
    }

    /// Calculate how much of a bolus was absorbed during a specific period
    /// Uses linear absorption model for simplicity
    private func calculateBolusAbsorption(
        bolusAmount: Double,
        bolusTime: Date,
        periodStart: Date,
        periodEnd: Date,
        insulinActionDuration: TimeInterval
    ) -> Double {
        let bolusEnd = bolusTime.addingTimeInterval(insulinActionDuration)

        // If bolus is completely before period or completely after, no absorption
        guard bolusTime < periodEnd && bolusEnd > periodStart else {
            return 0
        }

        // Calculate what fraction of the bolus absorption happened during the period
        let absorptionStart = max(bolusTime, periodStart)
        let absorptionEnd = min(bolusEnd, periodEnd)
        let periodAbsorptionDuration = absorptionEnd.timeIntervalSince(absorptionStart)

        // Linear absorption model: insulin absorbs evenly over the action duration
        let fractionAbsorbed = periodAbsorptionDuration / insulinActionDuration

        return bolusAmount * fractionAbsorbed
    }

    // MARK: - Carb Ratio Recommendations

    /// Generate carb ratio (I:C) recommendations based on meal analysis
    func generateCarbRatioRecommendations(daysToAnalyze: Int, completion: @escaping ([CarbRatioRecommendation], [RejectedMeal]) -> Void) {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(daysToAnalyze) * .hours(24))

        // Fetch all necessary data
        fetchAnalysisData(from: startDate, to: endDate) { result in
            switch result {
            case .success(let data):
                var rejectedMeals: [RejectedMeal] = []
                let mealWindows = self.identifyValidMealWindows(
                    glucoseSamples: data.glucoseSamples,
                    carbEntries: data.carbEntries,
                    doseEntries: data.doseEntries,
                    from: startDate,
                    to: endDate,
                    rejectedMeals: &rejectedMeals
                )

                let recommendations = self.generateCarbRatioRecommendations(
                    from: mealWindows,
                    glucoseSamples: data.glucoseSamples
                )
                completion(recommendations, rejectedMeals)

            case .failure(let error):
                self.logger.error("Failed to fetch analysis data for carb ratio: \(String(describing: error))")
                completion([], [])
            }
        }
    }

    /// Identify valid meal periods for carb ratio analysis
    private func identifyValidMealWindows(
        glucoseSamples: [StoredGlucoseSample],
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        from startDate: Date,
        to endDate: Date,
        rejectedMeals: inout [RejectedMeal]
    ) -> [CarbRatioAnalysisWindow] {
        var validWindows: [CarbRatioAnalysisWindow] = []

        // Analyze each carb entry
        for carbEntry in carbEntries {
            // Skip if carb entry is outside our analysis window
            guard carbEntry.startDate >= startDate && carbEntry.startDate <= endDate else { continue }

            // Try to create a valid analysis window for this meal
            var reasons: [String] = []
            if let window = analyzeMealPeriod(
                carbEntry: carbEntry,
                glucoseSamples: glucoseSamples,
                carbEntries: carbEntries,
                doseEntries: doseEntries,
                rejectionReasons: &reasons
            ) {
                validWindows.append(window)
            } else if !reasons.isEmpty {
                // Meal was rejected, add to rejected meals list
                let carbAmount = carbEntry.quantity.doubleValue(for: .gram())
                rejectedMeals.append(RejectedMeal(
                    carbEntry: carbEntry,
                    carbEntryTime: carbEntry.startDate,
                    carbAmount: carbAmount,
                    rejectionReasons: reasons
                ))
            }
        }

        return validWindows
    }

    /// Analyze a single meal period to see if it qualifies for carb ratio analysis
    private func analyzeMealPeriod(
        carbEntry: StoredCarbEntry,
        glucoseSamples: [StoredGlucoseSample],
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        rejectionReasons: inout [String]
    ) -> CarbRatioAnalysisWindow? {
        let mealTime = carbEntry.startDate
        let carbAmount = carbEntry.quantity.doubleValue(for: .gram())

        // Need at least 10g carbs for reliable analysis
        guard carbAmount >= 10.0 else {
            rejectionReasons.append("Less than 10g carbs (had \(String(format: "%.1f", carbAmount))g)")
            return nil
        }

        // Define maximum observation period (up to 8 hours for slow-absorbing carbs)
        let maxObservationEnd = mealTime.addingTimeInterval(8 * .hours(1))

        // Calculate when COB and IOB both reach near-zero
        // Use carb absorption time from the entry if available, otherwise estimate
        let carbAbsorptionTime = carbEntry.absorptionTime ?? TimeInterval(hours: 3)
        let estimatedCarbEnd = mealTime.addingTimeInterval(carbAbsorptionTime)

        // Insulin action duration (typically 6 hours)
        let insulinActionDuration: TimeInterval = 6 * .hours(1)

        // Find boluses around meal time to determine when insulin will be absorbed
        let bolusWindow: TimeInterval = 30 * 60
        let bolusStart = mealTime.addingTimeInterval(-bolusWindow)
        let bolusEnd = mealTime.addingTimeInterval(bolusWindow)

        let mealBoluses = doseEntries.filter { dose in
            dose.type == .bolus &&
            dose.startDate >= bolusStart &&
            dose.startDate <= bolusEnd
        }

        guard !mealBoluses.isEmpty else {
            rejectionReasons.append("No bolus found within 30 minutes of meal")
            return nil
        }

        // Latest bolus determines when insulin action ends
        let latestBolusTime = mealBoluses.map { $0.startDate }.max() ?? mealTime
        let estimatedInsulinEnd = latestBolusTime.addingTimeInterval(insulinActionDuration)

        // Observation ends when both carbs and insulin are absorbed
        // Use the later of the two, but cap at maximum observation period
        let observationEnd = min(max(estimatedCarbEnd, estimatedInsulinEnd), maxObservationEnd)

        // Check for minimal active carbs at meal time (< 1g COB)
        // This ensures we're starting with a clean slate
        let maxCarbAbsorptionDuration = 8 * .hours(1)
        var cobAtMealTime: Double = 0

        for otherCarb in carbEntries {
            guard otherCarb.syncIdentifier != carbEntry.syncIdentifier else { continue }

            let timeSinceCarb = mealTime.timeIntervalSince(otherCarb.startDate)

            // Only consider carbs that could still be active
            guard timeSinceCarb > 0 && timeSinceCarb < maxCarbAbsorptionDuration else { continue }

            // Estimate remaining carbs using simple linear absorption
            let carbAmount = otherCarb.quantity.doubleValue(for: .gram())
            let absorptionTime = otherCarb.absorptionTime ?? TimeInterval(hours: 3)
            let fractionRemaining = max(0, 1.0 - (timeSinceCarb / absorptionTime))
            cobAtMealTime += carbAmount * fractionRemaining
        }

        guard cobAtMealTime < 1.0 else {
            rejectionReasons.append("COB at meal time: \(String(format: "%.1f", cobAtMealTime))g (must be <1g)")
            return nil
        }

        // Check for no other carb entries during observation (only this single meal)
        let overlappingCarbs = carbEntries.filter { otherCarb in
            guard otherCarb.syncIdentifier != carbEntry.syncIdentifier else { return false }
            return otherCarb.startDate > mealTime && otherCarb.startDate <= observationEnd
        }

        guard overlappingCarbs.isEmpty else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let times = overlappingCarbs.map { formatter.string(from: $0.startDate) }.joined(separator: ", ")
            rejectionReasons.append("Overlapping carbs during observation at: \(times)")
            return nil
        }

        // Check for no recent lows (<4.0 mmol/L) within 8 hours before
        let lowGlucoseThreshold: Double = 72.0  // 4.0 mmol/L
        let lowCheckStart = mealTime.addingTimeInterval(-8 * .hours(1))

        let recentLows = glucoseSamples.filter { sample in
            sample.startDate >= lowCheckStart &&
            sample.startDate < mealTime &&
            sample.quantity.doubleValue(for: .milligramsPerDeciliter) < lowGlucoseThreshold
        }

        guard recentLows.isEmpty else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let lowTimes = recentLows.map { formatter.string(from: $0.startDate) }.joined(separator: ", ")
            rejectionReasons.append("Recent low detected (<4.0 mmol/L) at: \(lowTimes)")
            return nil
        }

        // Check for low active insulin at meal time (< 0.5 U)
        let iob = calculateActiveInsulin(
            doseEntries: doseEntries,
            at: mealTime,
            insulinActionDuration: insulinActionDuration
        )

        guard abs(iob) < 0.5 else {
            rejectionReasons.append("IOB at meal start: \(String(format: "%.2f", abs(iob)))U (must be <0.5U)")
            return nil
        }

        // Get start glucose for correction calculation
        guard let startGlucoseSample = glucoseSamples.filter({ $0.startDate >= mealTime && $0.startDate <= mealTime.addingTimeInterval(15 * 60) }).first else {
            rejectionReasons.append("No starting glucose reading within 15 minutes of meal")
            return nil
        }
        let startGlucose = startGlucoseSample.quantity.doubleValue(for: .milligramsPerDeciliter)

        // Calculate correction bolus component
        // If glucose is above target, Loop would have given correction insulin
        // Use the midpoint of the user's target range
        let targetRange = settings().glucoseTargetRangeSchedule?.quantityRange(at: mealTime)
        let targetGlucose: Double
        if let targetRange = targetRange {
            let minTarget = targetRange.lowerBound.doubleValue(for: .milligramsPerDeciliter)
            let maxTarget = targetRange.upperBound.doubleValue(for: .milligramsPerDeciliter)
            targetGlucose = (minTarget + maxTarget) / 2.0 // Use midpoint of target range
        } else {
            targetGlucose = 100.0 // Fallback: 5.5 mmol/L
        }

        let glucoseDelta = startGlucose - targetGlucose
        let isf = settings().insulinSensitivitySchedule?.quantity(at: mealTime).doubleValue(for: .milligramsPerDeciliter) ?? 72.0
        let estimatedCorrectionBolus = max(0, glucoseDelta / isf)

        // Total bolus given at meal time
        let totalBolus = mealBoluses.reduce(0.0) { $0 + $1.programmedUnits }

        // Separate meal bolus from correction
        // Meal bolus is what's left after accounting for correction
        let mealBolus = max(0.1, totalBolus - estimatedCorrectionBolus)
        let correctionBolus = totalBolus - mealBolus

        // Check for no correction boluses during observation period
        let observationBoluses = doseEntries.filter { dose in
            dose.type == .bolus &&
            dose.startDate > bolusEnd &&
            dose.startDate <= observationEnd
        }

        guard observationBoluses.isEmpty else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let bolusTimes = observationBoluses.map { formatter.string(from: $0.startDate) }.joined(separator: ", ")
            rejectionReasons.append("Correction bolus during observation at: \(bolusTimes)")
            return nil
        }

        // Get glucose readings during observation period
        let observationGlucose = glucoseSamples.filter { sample in
            sample.startDate >= mealTime && sample.startDate <= observationEnd
        }

        // Need sufficient glucose data (at least 4 readings, roughly one every hour for 4+ hours)
        guard observationGlucose.count >= 4 else {
            rejectionReasons.append("Insufficient glucose readings during observation (had \(observationGlucose.count), need at least 4)")
            return nil
        }

        // Check that glucose was within 4.0-13.0 mmol/L (72-234 mg/dL) for at least 2 hours
        if !isGlucoseInRangeForMinimumDuration(
            glucoseSamples: observationGlucose,
            measurementStart: mealTime,
            measurementEnd: observationEnd,
            minimumDuration: 2 * .hours(1)
        ) {
            rejectionReasons.append("Glucose out of range (4.0-13.0 mmol/L) for too long during observation")
            return nil
        }

        // Get start and end glucose values
        guard let startGlucose = glucoseSamples.filter({ $0.startDate >= mealTime && $0.startDate <= mealTime.addingTimeInterval(15 * 60) }).first,
              let endGlucose = observationGlucose.last else {
            rejectionReasons.append("Missing start or end glucose reading")
            return nil
        }

        // Create the valid meal analysis window
        return CarbRatioAnalysisWindow(
            carbEntryTime: mealTime,
            observationEnd: observationEnd,
            carbEntry: carbEntry,
            mealBolus: mealBolus,
            correctionBolus: correctionBolus,
            startGlucose: startGlucoseSample,
            endGlucose: endGlucose
        )
    }

    /// Generate carb ratio recommendations from valid meal windows
    private func generateCarbRatioRecommendations(
        from mealWindows: [CarbRatioAnalysisWindow],
        glucoseSamples: [StoredGlucoseSample]
    ) -> [CarbRatioRecommendation] {
        let calendar = Calendar.current
        let referenceDate = Date()
        let dayStart = calendar.startOfDay(for: referenceDate)

        guard !mealWindows.isEmpty else { return [] }

        // Group meals by hour of day
        var mealsByHour: [Int: [CarbRatioAnalysisWindow]] = [:]
        for meal in mealWindows {
            let hour = calendar.component(.hour, from: meal.carbEntryTime)
            mealsByHour[hour, default: []].append(meal)
        }

        var recommendations: [CarbRatioRecommendation] = []

        // Create recommendation for each hour that has meals
        let hoursWithMeals = mealsByHour.keys.sorted()
        for hour in hoursWithMeals {
            guard let mealsInHour = mealsByHour[hour], !mealsInHour.isEmpty else {
                continue
            }

            // Create hourly segment (e.g., 11:00-11:59)
            let segmentStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
            let segmentEnd = calendar.date(bySettingHour: hour, minute: 59, second: 59, of: dayStart) ?? dayStart

            // Calculate recommendation based on meals in this hour
            let rec = calculateCarbRatioRecommendation(
                meals: mealsInHour,
                segmentStart: segmentStart,
                segmentEnd: segmentEnd
            )
            recommendations.append(rec)
        }

        // Merge consecutive segments with same recommendation
        return mergeCarbRatioRecommendations(recommendations)
    }

    /// Calculate carb ratio recommendation for a group of meals
    private func calculateCarbRatioRecommendation(
        meals: [CarbRatioAnalysisWindow],
        segmentStart: Date,
        segmentEnd: Date
    ) -> CarbRatioRecommendation {
        let calendar = Calendar.current
        let hourOfDay = calendar.component(.hour, from: segmentStart)

        // Get current carb ratio setting
        let currentRatio = settings().carbRatioSchedule?.value(at: segmentStart) ?? 10.0

        // Analyze each meal to determine optimal ratio
        var totalWeightedRatio: Double = 0
        var totalGlucoseChange: Double = 0
        var totalStartGlucose: Double = 0
        var totalEndGlucose: Double = 0
        var totalWeight: Double = 0

        for meal in meals {
            let carbAmount = meal.carbAmount
            let mealBolus = meal.mealBolus
            let glucoseChange = meal.glucoseChange

            // Weight by carb amount (larger meals have more data)
            let weight = carbAmount

            // Calculate what ratio would have resulted in stable glucose
            // If glucose rose, need more insulin (lower ratio = more insulin per carb)
            // If glucose fell, need less insulin (higher ratio = less insulin per carb)

            // Use ISF to estimate how much the insulin affected glucose
            // Make sure we get ISF in mg/dL units to match glucoseChange
            let isfSchedule = settings().insulinSensitivitySchedule
            let isf = isfSchedule?.quantity(at: meal.carbEntryTime).doubleValue(for: .milligramsPerDeciliter) ?? 50.0

            // Account for correction bolus effect on glucose
            // The correction bolus lowered glucose by: correctionBolus * isf
            // So the net effect from carbs and meal insulin is:
            let correctionEffect = meal.correctionBolus * isf
            let netGlucoseChangeFromMeal = glucoseChange + correctionEffect

            // Now calculate adjustment needed for meal insulin
            // If netGlucoseChangeFromMeal > 0: meal bolus was too little
            // If netGlucoseChangeFromMeal < 0: meal bolus was too much
            let mealInsulinAdjustment = netGlucoseChangeFromMeal / isf
            let optimalMealInsulin = mealBolus + mealInsulinAdjustment

            // Calculate optimal ratio, with bounds checking
            var adjustedRatio: Double
            if optimalMealInsulin > 0.1 {
                adjustedRatio = carbAmount / optimalMealInsulin
                // Clamp to reasonable range (1-30 g/U)
                adjustedRatio = max(1.0, min(30.0, adjustedRatio))
            } else {
                // If optimal insulin is near zero or negative, use observed ratio
                adjustedRatio = meal.observedCarbRatio
            }

            print("Meal analysis: carbs=\(carbAmount)g, meal insulin=\(mealBolus)U, correction=\(meal.correctionBolus)U, observed ratio=\(meal.observedCarbRatio), glucose change=\(glucoseChange)mg/dL, net change from meal=\(netGlucoseChangeFromMeal)mg/dL, ISF=\(isf), adjustment=\(mealInsulinAdjustment)U, optimal meal insulin=\(optimalMealInsulin)U, adjusted ratio=\(adjustedRatio)g/U")

            totalWeightedRatio += adjustedRatio * weight
            totalGlucoseChange += glucoseChange * weight
            totalStartGlucose += meal.startGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) * weight
            totalEndGlucose += meal.endGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) * weight
            totalWeight += weight
        }

        let recommendedRatio = totalWeight > 0 ? totalWeightedRatio / totalWeight : currentRatio
        let avgGlucoseChange = totalWeight > 0 ? totalGlucoseChange / totalWeight : 0
        let avgStartGlucose = totalWeight > 0 ? totalStartGlucose / totalWeight : 0
        let avgEndGlucose = totalWeight > 0 ? totalEndGlucose / totalWeight : 0

        // Round to 1 decimal place (e.g., 7.33 -> 7.3)
        let roundedRatio = max(1.0, round(recommendedRatio * 10) / 10)

        // Calculate confidence based on meal count
        let confidence = min(1.0, Double(meals.count) / 5.0)

        return CarbRatioRecommendation(
            hourOfDay: hourOfDay,
            startDate: segmentStart,
            endDate: segmentEnd,
            currentCarbRatio: currentRatio,
            recommendedCarbRatio: roundedRatio,
            averageGlucoseChange: avgGlucoseChange,
            averageStartGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgStartGlucose),
            averageEndGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgEndGlucose),
            confidence: confidence,
            mealCount: meals.count,
            qualifyingMeals: meals
        )
    }

    /// Merge consecutive carb ratio recommendations with same ratio
    private func mergeCarbRatioRecommendations(_ recs: [CarbRatioRecommendation]) -> [CarbRatioRecommendation] {
        guard !recs.isEmpty else { return [] }

        var merged: [CarbRatioRecommendation] = []
        var currentGroup: [CarbRatioRecommendation] = [recs[0]]

        for i in 1..<recs.count {
            let prev = recs[i - 1]
            let current = recs[i]

            // Only merge if both have data and same ratio (within 0.1 tolerance for rounding)
            let bothHaveData = prev.mealCount > 0 && current.mealCount > 0
            let sameRatio = abs(current.recommendedCarbRatio - prev.recommendedCarbRatio) < 0.15

            // Check if hours are consecutive
            let calendar = Calendar.current
            let prevHour = calendar.component(.hour, from: prev.endDate)
            let currentHour = calendar.component(.hour, from: current.startDate)
            let consecutive = (currentHour == (prevHour + 1) % 24) || (prevHour == 23 && currentHour == 0)

            if bothHaveData && sameRatio && consecutive {
                currentGroup.append(current)
            } else {
                if let mergedRec = createMergedCarbRatioRecommendation(from: currentGroup) {
                    merged.append(mergedRec)
                }
                currentGroup = [current]
            }
        }

        if let mergedRec = createMergedCarbRatioRecommendation(from: currentGroup) {
            merged.append(mergedRec)
        }

        return merged
    }

    /// Create merged carb ratio recommendation from group
    private func createMergedCarbRatioRecommendation(from group: [CarbRatioRecommendation]) -> CarbRatioRecommendation? {
        guard let first = group.first, let last = group.last else { return nil }

        let totalMealCount = group.reduce(0) { $0 + $1.mealCount }
        let allMeals = group.flatMap { $0.qualifyingMeals }

        var weightedChange: Double = 0
        var weightedStartGlucose: Double = 0
        var weightedEndGlucose: Double = 0
        var weightedConfidence: Double = 0
        var weightedCurrentRatio: Double = 0

        for rec in group {
            let weight = Double(rec.mealCount)
            weightedChange += rec.averageGlucoseChange * weight
            weightedStartGlucose += rec.averageStartGlucose.doubleValue(for: .milligramsPerDeciliter) * weight
            weightedEndGlucose += rec.averageEndGlucose.doubleValue(for: .milligramsPerDeciliter) * weight
            weightedConfidence += rec.confidence * weight
            weightedCurrentRatio += rec.currentCarbRatio * weight
        }

        let totalWeight = Double(totalMealCount)
        let avgChange = totalWeight > 0 ? weightedChange / totalWeight : 0
        let avgStart = totalWeight > 0 ? weightedStartGlucose / totalWeight : 0
        let avgEnd = totalWeight > 0 ? weightedEndGlucose / totalWeight : 0
        let avgConfidence = totalWeight > 0 ? weightedConfidence / totalWeight : 0
        let avgCurrent = totalWeight > 0 ? weightedCurrentRatio / totalWeight : first.currentCarbRatio

        return CarbRatioRecommendation(
            hourOfDay: first.hourOfDay,
            startDate: first.startDate,
            endDate: last.endDate,
            currentCarbRatio: avgCurrent,
            recommendedCarbRatio: first.recommendedCarbRatio,
            averageGlucoseChange: avgChange,
            averageStartGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgStart),
            averageEndGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: avgEnd),
            confidence: avgConfidence,
            mealCount: totalMealCount,
            qualifyingMeals: allMeals
        )
    }
}
