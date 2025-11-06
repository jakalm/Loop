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

                    Text("Includes 3 hours before and after for context")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if detailViewModel.isLoading {
                    ProgressView("Loading period data...")
                        .padding()
                } else {
                    // Glucose Chart
                    if !detailViewModel.glucoseSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Blood Glucose")
                                .font(.headline)

                            LoopChartView(chartManager: detailViewModel.chartsManager, chartIndex: StatusChartsManager.ChartIndex.glucose.rawValue)
                                .frame(height: 200)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Active Insulin (IOB) Chart
                    if !detailViewModel.iobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Insulin (IOB)")
                                .font(.headline)

                            LoopChartView(chartManager: detailViewModel.chartsManager, chartIndex: StatusChartsManager.ChartIndex.iob.rawValue)
                                .frame(height: 100)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Basal Rate Chart
                    if !detailViewModel.basalDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Basal Insulin Rate")
                                .font(.headline)

                            BasalRateChartView(basalDoses: detailViewModel.basalDoses, period: detailViewModel.displayPeriod)
                                .frame(height: 100)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Insulin Doses Chart
                    if !detailViewModel.insulinDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insulin Doses")
                                .font(.headline)

                            LoopChartView(chartManager: detailViewModel.chartsManager, chartIndex: StatusChartsManager.ChartIndex.dose.rawValue)
                                .frame(height: 100)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Active Carbs (COB) Chart
                    if !detailViewModel.cobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Carbs (COB)")
                                .font(.headline)

                            LoopChartView(chartManager: detailViewModel.chartsManager, chartIndex: StatusChartsManager.ChartIndex.cob.rawValue)
                                .frame(height: 100)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Show message if no data
                    if detailViewModel.glucoseSamples.isEmpty &&
                       detailViewModel.iobValues.isEmpty &&
                       detailViewModel.insulinDoses.isEmpty &&
                       detailViewModel.basalDoses.isEmpty &&
                       detailViewModel.cobValues.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)

                            Text("No data available for this period")
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

    private let window: BasalAnalysisWindow
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    var glucoseUnit: HKUnit = .milligramsPerDeciliter

    var displayPeriod: (start: Date, end: Date) {
        let extendedStart = window.measurementStart.addingTimeInterval(-3 * .hours(1))
        let extendedEnd = window.measurementEnd.addingTimeInterval(3 * .hours(1))
        return (extendedStart, extendedEnd)
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

        // Extend period by 3 hours on each side
        let extendedStart = window.measurementStart.addingTimeInterval(-3 * .hours(1))
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
            self.updateCharts()
        }
    }

    private func updateCharts() {
        let extendedStart = window.measurementStart.addingTimeInterval(-3 * .hours(1))
        let extendedEnd = window.measurementEnd.addingTimeInterval(3 * .hours(1))

        // Update date range
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
    }
}

// MARK: - Custom Charts Manager for Period Detail

class PeriodDetailChartsManager: ChartsManager {
    enum ChartIndex: Int, CaseIterable {
        case glucose
        case iob
        case dose
        case cob
    }

    let glucose: PredictedGlucoseChart
    let iob: IOBChart
    let dose: DoseChart
    let cob: COBChart

    init(colors: ChartColorPalette, settings: ChartSettings, traitCollection: UITraitCollection) {
        let glucose = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        let iob = IOBChart()
        let dose = DoseChart()
        let cob = COBChart()
        self.glucose = glucose
        self.iob = iob
        self.dose = dose
        self.cob = cob

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
}

// MARK: - Basal Rate Chart View

struct BasalRateChartView: View {
    let basalDoses: [DoseEntry]
    let period: (start: Date, end: Date)

    var body: some View {
        HStack(spacing: 0) {
            // Y-axis labels
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<6) { i in
                    if let maxRate = getMaxRate() {
                        let rate = maxRate * 1.2 * (1.0 - Double(i) / 5.0)
                        Text(String(format: "%.2f", rate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(height: 20, alignment: .center)
                        if i < 5 {
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 40)
            .padding(.trailing, 4)

            VStack(spacing: 0) {
                // Chart area
                GeometryReader { geometry in
                    if let chartData = createChartData() {
                        Canvas { context, size in
                            // Draw grid lines
                            let gridColor = Color.gray.opacity(0.2)
                            for i in 0...5 {
                                let y = CGFloat(i) * (size.height / 5)
                                context.stroke(
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: size.width, y: y))
                                    },
                                    with: .color(gridColor),
                                    lineWidth: 0.5
                                )
                            }

                            // Draw basal rate line
                            let path = Path { path in
                                for (index, point) in chartData.enumerated() {
                                    let x = point.x * size.width
                                    let y = size.height - (point.y * size.height)

                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }

                            context.stroke(
                                path,
                                with: .color(.blue),
                                lineWidth: 2
                            )

                            // Fill area under line
                            let fillPath = Path { path in
                                for (index, point) in chartData.enumerated() {
                                    let x = point.x * size.width
                                    let y = size.height - (point.y * size.height)

                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: size.height))
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                                if let last = chartData.last {
                                    path.addLine(to: CGPoint(x: last.x * size.width, y: size.height))
                                }
                                path.closeSubpath()
                            }

                            context.fill(
                                fillPath,
                                with: .color(.blue.opacity(0.2))
                            )
                        }
                    } else {
                        Text("No basal data")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }

                // X-axis labels
                HStack(spacing: 0) {
                    ForEach(0..<7) { i in
                        let fraction = Double(i) / 6.0
                        let time = period.start.addingTimeInterval(period.end.timeIntervalSince(period.start) * fraction)
                        Text(formatTime(time))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    private func getMaxRate() -> Double? {
        return basalDoses.map { $0.unitsPerHour }.max()
    }

    private func createChartData() -> [(x: CGFloat, y: CGFloat)]? {
        guard !basalDoses.isEmpty else { return nil }

        // Get max rate for scaling
        let maxRate = basalDoses.map { $0.unitsPerHour }.max() ?? 1.0
        let scaledMaxRate = maxRate * 1.2 // Add 20% padding

        let totalDuration = period.end.timeIntervalSince(period.start)

        var points: [(x: CGFloat, y: CGFloat)] = []

        // Create points for each basal segment
        for dose in basalDoses.sorted(by: { $0.startDate < $1.startDate }) {
            let startX = max(0, dose.startDate.timeIntervalSince(period.start) / totalDuration)
            let endX = min(1, dose.endDate.timeIntervalSince(period.start) / totalDuration)

            // Skip if dose is completely outside period
            guard endX > 0 && startX < 1 else { continue }

            let rate = dose.type == .suspend ? 0 : dose.unitsPerHour
            let y = CGFloat(rate / scaledMaxRate)

            // Add start point
            points.append((x: CGFloat(startX), y: y))
            // Add end point
            points.append((x: CGFloat(endX), y: y))
        }

        return points.isEmpty ? nil : points
    }
}

// MARK: - Chart View Wrapper

struct LoopChartView: UIViewRepresentable {
    let chartManager: ChartsManager
    let chartIndex: Int

    func makeUIView(context: Context) -> ChartContainerView {
        let view = ChartContainerView()
        view.chartGenerator = { [chartManager, chartIndex] frame in
            chartManager.chart(atIndex: chartIndex, frame: frame)?.view
        }
        return view
    }

    func updateUIView(_ chartContainerView: ChartContainerView, context: Context) {
        chartManager.invalidateChart(atIndex: chartIndex)
        chartManager.prerender()
        chartContainerView.reloadChart()
    }
}
