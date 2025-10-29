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
    private let minimumCarbFreeHours: TimeInterval = 3 * .hours(1)
    private let minimumMeasurementHours: TimeInterval = 3 * .hours(1)
    private let analysisWindowStride: TimeInterval = 1 * .hours(1) // Check every hour
    private let daysToAnalyze = 14

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
    func generateBasalRateRecommendations(completion: @escaping ([BasalRateRecommendation]) -> Void) {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-TimeInterval(daysToAnalyze) * .hours(24))

        // Fetch all necessary data
        fetchAnalysisData(from: startDate, to: endDate) { result in
            switch result {
            case .success(let data):
                let windows = self.identifyValidAnalysisWindows(
                    glucoseSamples: data.glucoseSamples,
                    carbEntries: data.carbEntries,
                    doseEntries: data.doseEntries,
                    from: startDate,
                    to: endDate
                )

                let recommendations = self.generateRecommendations(from: windows, glucoseSamples: data.glucoseSamples)
                completion(recommendations)

            case .failure(let error):
                self.logger.error("Failed to fetch analysis data: \(String(describing: error))")
                completion([])
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

        // Fetch carbs via getGlucoseEffects (which returns entries)
        group.enter()
        carbStore.getGlucoseEffects(start: startDate, end: endDate, effectVelocities: []) { result in
            switch result {
            case .success(let data):
                carbEntries = data.entries
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
    ) -> [BasalAnalysisWindow] {
        var windows: [BasalAnalysisWindow] = []
        var currentDate = startDate

        while currentDate < endDate {
            let measurementStart = currentDate
            let measurementEnd = measurementStart.addingTimeInterval(minimumMeasurementHours)
            let carbFreeStart = measurementStart.addingTimeInterval(-minimumCarbFreeHours)

            // Check if this window is valid
            if isValidAnalysisWindow(
                carbFreeStart: carbFreeStart,
                measurementStart: measurementStart,
                measurementEnd: measurementEnd,
                carbEntries: carbEntries,
                doseEntries: doseEntries,
                glucoseSamples: glucoseSamples
            ) {
                windows.append(BasalAnalysisWindow(
                    measurementStart: measurementStart,
                    measurementEnd: measurementEnd,
                    carbFreeStart: carbFreeStart
                ))
            }

            currentDate = currentDate.addingTimeInterval(analysisWindowStride)
        }

        return windows
    }

    private func isValidAnalysisWindow(
        carbFreeStart: Date,
        measurementStart: Date,
        measurementEnd: Date,
        carbEntries: [StoredCarbEntry],
        doseEntries: [DoseEntry],
        glucoseSamples: [StoredGlucoseSample]
    ) -> Bool {
        // Check for carbs in the entire period
        let carbsInPeriod = carbEntries.filter { carb in
            let carbStart = carb.startDate
            // Check if carb would still be active during our window
            // Assuming max absorption of 8 hours
            let carbEndImpact = carbStart.addingTimeInterval(.hours(8))
            return carbEndImpact > carbFreeStart && carbStart < measurementEnd
        }

        if !carbsInPeriod.isEmpty {
            return false
        }

        // Check for boluses or temp basals in the measurement period
        let dosesInPeriod = doseEntries.filter { dose in
            let doseEnd = dose.endDate
            let doseStart = dose.startDate

            // Check if dose overlaps with our analysis window
            return doseStart < measurementEnd && doseEnd > carbFreeStart
        }

        // Filter to only non-basal doses (boluses, corrections) or temp basals
        let invalidDoses = dosesInPeriod.filter { dose in
            switch dose.type {
            case .bolus, .resume, .suspend:
                return true
            case .tempBasal:
                // Temp basal is invalid if it's different from scheduled basal
                return true
            case .basal:
                return false
            }
        }

        if !invalidDoses.isEmpty {
            return false
        }

        // Check for sufficient glucose data
        let glucoseInWindow = glucoseSamples.filter { sample in
            sample.startDate >= measurementStart && sample.startDate <= measurementEnd
        }

        // Need at least 6 readings (one every 30 min for 3 hours)
        if glucoseInWindow.count < 6 {
            return false
        }

        return true
    }

    private func generateRecommendations(
        from windows: [BasalAnalysisWindow],
        glucoseSamples: [StoredGlucoseSample]
    ) -> [BasalRateRecommendation] {
        // Group windows by hour of day
        let windowsByHour = Dictionary(grouping: windows) { $0.hourOfDay }

        var recommendations: [BasalRateRecommendation] = []

        for (hour, hourWindows) in windowsByHour.sorted(by: { $0.key < $1.key }) {
            guard !hourWindows.isEmpty else { continue }

            var totalTrend: Double = 0
            var validWindowCount = 0
            var startGlucoseValues: [HKQuantity] = []
            var endGlucoseValues: [HKQuantity] = []

            for window in hourWindows {
                let windowGlucose = glucoseSamples.filter { sample in
                    sample.startDate >= window.measurementStart && sample.startDate <= window.measurementEnd
                }.sorted { $0.startDate < $1.startDate }

                guard let firstGlucose = windowGlucose.first,
                      let lastGlucose = windowGlucose.last else { continue }

                // Calculate trend (mg/dL per hour)
                let glucoseChange = lastGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) -
                                  firstGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)
                let durationHours = window.duration / .hours(1)
                let trend = glucoseChange / durationHours

                totalTrend += trend
                validWindowCount += 1
                startGlucoseValues.append(firstGlucose.quantity)
                endGlucoseValues.append(lastGlucose.quantity)
            }

            guard validWindowCount > 0 else { continue }

            let averageTrend = totalTrend / Double(validWindowCount)

            // Get current basal rate for this hour
            let sampleDate = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            let currentBasal = settings().basalRateSchedule?.value(at: sampleDate) ?? 0.0

            // Calculate recommended adjustment
            // Rule of thumb: ~1 mg/dL/hour change suggests ~0.05 U/hr adjustment needed
            let basalAdjustment = averageTrend * 0.05 / 10.0
            let recommendedBasal = max(0, currentBasal - basalAdjustment)

            // Calculate confidence based on sample count and trend consistency
            let confidence = min(1.0, Double(validWindowCount) / 10.0)

            let avgStartGlucose = startGlucoseValues.reduce(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)) { result, quantity in
                HKQuantity(unit: .milligramsPerDeciliter,
                          doubleValue: result.doubleValue(for: .milligramsPerDeciliter) + quantity.doubleValue(for: .milligramsPerDeciliter))
            }
            let avgStart = HKQuantity(unit: .milligramsPerDeciliter,
                                     doubleValue: avgStartGlucose.doubleValue(for: .milligramsPerDeciliter) / Double(startGlucoseValues.count))

            let avgEndGlucose = endGlucoseValues.reduce(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0)) { result, quantity in
                HKQuantity(unit: .milligramsPerDeciliter,
                          doubleValue: result.doubleValue(for: .milligramsPerDeciliter) + quantity.doubleValue(for: .milligramsPerDeciliter))
            }
            let avgEnd = HKQuantity(unit: .milligramsPerDeciliter,
                                   doubleValue: avgEndGlucose.doubleValue(for: .milligramsPerDeciliter) / Double(endGlucoseValues.count))

            let recommendation = BasalRateRecommendation(
                startDate: hourWindows.first!.measurementStart,
                endDate: hourWindows.last!.measurementEnd,
                hourOfDay: hour,
                currentBasalRate: currentBasal,
                recommendedBasalRate: recommendedBasal,
                glucoseTrend: averageTrend,
                startGlucose: avgStart,
                endGlucose: avgEnd,
                confidence: confidence,
                sampleCount: validWindowCount
            )

            recommendations.append(recommendation)
        }

        return recommendations
    }
}
