//
//  PeriodDetailView.swift
//  Loop
//
//  Created by Claude Code for Period Detail View
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import LoopUI
import SwiftCharts

// MARK: - Periods List View

struct PeriodsListView: View {
    let recommendation: BasalRateRecommendation
    let viewModel: BasalRateRecommendationsViewModel

    var body: some View {
        List {
            Section(header: Text("Qualifying Periods (\(recommendation.qualifyingWindows.count))")) {
                ForEach(recommendation.qualifyingWindows.indices, id: \.self) { index in
                    let window = recommendation.qualifyingWindows[index]
                    NavigationLink(destination: PeriodDetailView(
                        window: window,
                        viewModel: viewModel
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatPeriodRange(window.measurementStart, window.measurementEnd))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Duration: \(formatDuration(window.duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Time Block: \(formatTimeBlock())")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatTimeBlock() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: recommendation.startDate)) - \(formatter.string(from: recommendation.endDate))"
    }

    private func formatPeriodRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Period Detail View

struct PeriodDetailView: View {
    let window: BasalAnalysisWindow
    let viewModel: BasalRateRecommendationsViewModel

    @StateObject private var detailViewModel: PeriodDetailViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    init(window: BasalAnalysisWindow, viewModel: BasalRateRecommendationsViewModel) {
        self.window = window
        self.viewModel = viewModel
        let vm = PeriodDetailViewModel(
            window: window,
            glucoseStore: viewModel.glucoseStore,
            carbStore: viewModel.carbStore,
            doseStore: viewModel.doseStore
        )
        _detailViewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Period Details")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(formatPeriodRange(window.measurementStart, window.measurementEnd))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Includes 8 hours before and 3 hours after for context")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if detailViewModel.isLoading {
                    ProgressView("Loading period data...")
                        .padding()
                } else {
                    // Insulin Absorption Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Insulin Absorption Analysis")
                            .font(.headline)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Absorbed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f U", detailViewModel.totalAbsorbedInsulin))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Absorption Rate")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f U/hr", detailViewModel.averageInsulinPerHour))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDuration(window.duration))
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                        }

                        Text("Includes basal, temp basal, and absorbed bolus insulin during the measurement period")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Glucose chart
                    if !detailViewModel.glucoseSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Glucose")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: StatusChartsManager.ChartIndex.glucose.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 200)
                        }
                    }

                    // IOB chart
                    if !detailViewModel.iobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Insulin (IOB)")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: StatusChartsManager.ChartIndex.iob.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    // COB chart
                    if !detailViewModel.cobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Carbs (COB)")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: StatusChartsManager.ChartIndex.cob.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    // Basal rate chart
                    if !detailViewModel.basalDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Basal Insulin Rate")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: PeriodDetailChartsManager.ChartIndex.basalRate.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    // Dose chart
                    if !detailViewModel.insulinDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insulin Doses")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: StatusChartsManager.ChartIndex.dose.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    // Show message if no chart data
                    if detailViewModel.glucoseSamples.isEmpty &&
                       detailViewModel.iobValues.isEmpty &&
                       detailViewModel.cobValues.isEmpty &&
                       detailViewModel.basalDoses.isEmpty &&
                       detailViewModel.insulinDoses.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)

                            Text("No chart data available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Set glucose unit from environment
            detailViewModel.glucoseUnit = displayGlucosePreference.unit
            detailViewModel.loadData()
        }
    }

    private func formatPeriodRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - View Model

class PeriodDetailViewModel: ObservableObject {
    @Published var glucoseSamples: [StoredGlucoseSample] = []
    @Published var insulinDoses: [DoseEntry] = []
    @Published var basalDoses: [DoseEntry] = []
    @Published var carbEntries: [StoredCarbEntry] = []
    @Published var iobValues: [InsulinValue] = []
    @Published var cobValues: [CarbValue] = []
    @Published var isLoading = false
    @Published var totalAbsorbedInsulin: Double = 0
    @Published var averageInsulinPerHour: Double = 0

    private let window: BasalAnalysisWindow
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    var glucoseUnit: HKUnit = .milligramsPerDeciliter

    var displayPeriod: (start: Date, end: Date) {
        let extendedStart = window.measurementStart.addingTimeInterval(-8 * .hours(1))
        let extendedEnd = window.measurementEnd.addingTimeInterval(3 * .hours(1))
        return (extendedStart, extendedEnd)
    }

    var measurementPeriod: (start: Date, end: Date) {
        return (window.measurementStart, window.measurementEnd)
    }

    // Chart managers
    lazy var chartsManager: PeriodDetailChartsManager = {
        let colors = ChartColorPalette(
            axisLine: .axisLineColor,
            axisLabel: .axisLabelColor,
            grid: .gridColor,
            glucoseTint: .glucoseTintColor,
            insulinTint: .insulinTintColor,
            carbTint: .carbTintColor
        )
        var settings = ChartSettings()
        settings.top = 12
        settings.bottom = 0
        settings.trailing = 8
        settings.axisTitleLabelsToLabelsSpacing = 0
        settings.labelsToAxisSpacingX = 6
        return PeriodDetailChartsManager(colors: colors, settings: settings, traitCollection: .current)
    }()

    init(window: BasalAnalysisWindow,
         glucoseStore: GlucoseStoreProtocol,
         carbStore: CarbStoreProtocol,
         doseStore: DoseStoreProtocol) {
        self.window = window
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
    }

    func loadData() {
        isLoading = true

        // Extend period by 8 hours before and 3 hours after
        let extendedStart = window.measurementStart.addingTimeInterval(-8 * .hours(1))
        let extendedEnd = window.measurementEnd.addingTimeInterval(3 * .hours(1))

        let group = DispatchGroup()

        // Load glucose
        group.enter()
        glucoseStore.getGlucoseSamples(start: extendedStart, end: extendedEnd) { result in
            if case .success(let samples) = result {
                DispatchQueue.main.async {
                    self.glucoseSamples = samples
                }
            }
            group.leave()
        }

        // Load carbs
        group.enter()
        carbStore.getGlucoseEffects(start: extendedStart, end: extendedEnd, effectVelocities: []) { result in
            if case .success(let data) = result {
                DispatchQueue.main.async {
                    self.carbEntries = data.entries
                }
            }
            group.leave()
        }

        // Load insulin doses
        group.enter()
        doseStore.getNormalizedDoseEntries(start: extendedStart, end: extendedEnd) { result in
            if case .success(let doses) = result {
                DispatchQueue.main.async {
                    // Separate basal doses from other insulin doses
                    self.basalDoses = doses.filter { $0.type == .basal || $0.type == .tempBasal || $0.type == .suspend }
                    self.insulinDoses = doses.filter { $0.type != .basal }
                }
            }
            group.leave()
        }

        // Load IOB
        group.enter()
        doseStore.getInsulinOnBoardValues(start: extendedStart, end: extendedEnd, basalDosingEnd: nil) { result in
            if case .success(let iobValues) = result {
                DispatchQueue.main.async {
                    self.iobValues = iobValues
                }
            }
            group.leave()
        }

        // Load COB
        group.enter()
        carbStore.getCarbsOnBoardValues(start: extendedStart, end: extendedEnd, effectVelocities: []) { result in
            if case .success(let cobValues) = result {
                DispatchQueue.main.async {
                    self.cobValues = cobValues
                }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.isLoading = false
            self.calculateInsulinAbsorption()
            self.updateCharts()
        }
    }

    private func calculateInsulinAbsorption() {
        let insulinActionDuration: TimeInterval = 6 * .hours(1)
        var totalAbsorbed: Double = 0

        // Look back to include any insulin doses that could still be absorbing during the period
        let lookbackStart = window.measurementStart.addingTimeInterval(-insulinActionDuration)

        // Get all doses that could affect the measurement period
        let allDoses = insulinDoses + basalDoses

        let relevantDoses = allDoses.filter { dose in
            dose.endDate > lookbackStart && dose.startDate < window.measurementEnd
        }

        for dose in relevantDoses {
            switch dose.type {
            case .bolus:
                // Calculate how much of the bolus was absorbed during the period
                let bolusAbsorbed = calculateBolusAbsorption(
                    bolusAmount: dose.programmedUnits,
                    bolusTime: dose.startDate,
                    periodStart: window.measurementStart,
                    periodEnd: window.measurementEnd,
                    insulinActionDuration: insulinActionDuration
                )
                totalAbsorbed += bolusAbsorbed

            case .basal, .tempBasal:
                // Calculate basal/temp basal delivered during the period
                let overlapStart = max(dose.startDate, window.measurementStart)
                let overlapEnd = min(dose.endDate, window.measurementEnd)

                if overlapStart < overlapEnd {
                    let overlapDuration = overlapEnd.timeIntervalSince(overlapStart) / .hours(1)
                    let insulinDelivered = dose.unitsPerHour * overlapDuration
                    totalAbsorbed += insulinDelivered
                }

            case .suspend, .resume:
                // No insulin
                break
            }
        }

        let durationHours = window.duration / .hours(1)
        self.totalAbsorbedInsulin = totalAbsorbed
        self.averageInsulinPerHour = durationHours > 0 ? totalAbsorbed / durationHours : 0
    }

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

    private func updateCharts() {
        let extendedStart = window.measurementStart.addingTimeInterval(-8 * .hours(1))
        let extendedEnd = window.measurementEnd.addingTimeInterval(3 * .hours(1))

        // Update date range - set maxEndDate first to prevent rounding up
        chartsManager.maxEndDate = extendedEnd
        chartsManager.startDate = extendedStart
        chartsManager.updateEndDate(extendedEnd)

        // Set glucose unit
        chartsManager.glucose.glucoseUnit = glucoseUnit

        // Update glucose chart - only if we have data
        if !glucoseSamples.isEmpty {
            let glucoseValues = glucoseSamples.map { SimpleGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
            chartsManager.setGlucoseValues(glucoseValues)
        }

        // Update IOB chart - only if we have data
        if !iobValues.isEmpty {
            chartsManager.setIOBValues(iobValues)
        }

        // Update dose chart - only if we have data
        if !insulinDoses.isEmpty {
            chartsManager.setDoseEntries(insulinDoses)
        }

        // Update COB chart - only if we have data
        if !cobValues.isEmpty {
            chartsManager.setCOBValues(cobValues)
        }

        // Update basal rate chart - only if we have data
        if !basalDoses.isEmpty {
            chartsManager.setBasalDoses(basalDoses)
        }
    }
}

// MARK: - Custom Charts Manager for Period Detail

class PeriodDetailChartsManager: ChartsManager {
    enum ChartIndex: Int, CaseIterable {
        case glucose
        case iob
        case dose
        case cob
        case basalRate
    }

    let glucose: PredictedGlucoseChart
    let iob: IOBChart
    let dose: DoseChart
    let cob: COBChart
    let basalRate: BasalRateChart

    init(colors: ChartColorPalette, settings: ChartSettings, traitCollection: UITraitCollection) {
        let glucose = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        let iob = IOBChart()
        let dose = DoseChart()
        let cob = COBChart()
        let basalRate = BasalRateChart()
        self.glucose = glucose
        self.iob = iob
        self.dose = dose
        self.cob = cob
        self.basalRate = basalRate

        // Create custom time formatter that shows just the hour
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH"  // Shows "01", "02", "13", "14", etc.

        super.init(colors: colors, settings: settings, charts: ChartIndex.allCases.map({ (index) -> ChartProviding in
            switch index {
            case .glucose:
                return glucose
            case .iob:
                return iob
            case .dose:
                return dose
            case .cob:
                return cob
            case .basalRate:
                return basalRate
            }
        }), traitCollection: traitCollection, customTimeFormatter: hourFormatter)
    }
}

extension PeriodDetailChartsManager {
    func setGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucose.setGlucoseValues(glucoseValues)
        invalidateChart(atIndex: ChartIndex.glucose.rawValue)
    }

    func setIOBValues(_ iobValues: [InsulinValue]) {
        iob.setIOBValues(iobValues)
        invalidateChart(atIndex: ChartIndex.iob.rawValue)
    }

    func setDoseEntries(_ doseEntries: [DoseEntry]) {
        dose.doseEntries = doseEntries
        invalidateChart(atIndex: ChartIndex.dose.rawValue)
    }

    func setCOBValues(_ cobValues: [CarbValue]) {
        cob.setCOBValues(cobValues)
        invalidateChart(atIndex: ChartIndex.cob.rawValue)
    }

    func setBasalDoses(_ basalDoses: [DoseEntry]) {
        basalRate.setBasalDoses(basalDoses)
        invalidateChart(atIndex: ChartIndex.basalRate.rawValue)
    }
}

// MARK: - Chart View Wrapper

struct LoopChartView: UIViewRepresentable {
    let chartManager: ChartsManager
    let chartIndex: Int
    var measurementPeriod: (start: Date, end: Date)? = nil

    func makeUIView(context: Context) -> ChartContainerView {
        let view = ChartContainerView()
        view.chartGenerator = { [chartManager, chartIndex] frame in
            chartManager.chart(atIndex: chartIndex, frame: frame)?.view
        }
        return view
    }

    func updateUIView(_ chartContainerView: ChartContainerView, context: Context) {
        chartManager.highlightedTimeRange = measurementPeriod
        chartManager.invalidateChart(atIndex: chartIndex)
        chartManager.prerender()
        chartContainerView.reloadChart()
    }
}
