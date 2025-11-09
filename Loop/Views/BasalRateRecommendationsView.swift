//
//  BasalRateRecommendationsView.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import LoopUI
import SwiftCharts

public struct BasalRateRecommendationsView: View {
    @StateObject private var viewModel: BasalRateRecommendationsViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @State private var showAllRejectedPeriods = false

    public init(viewModel: BasalRateRecommendationsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Basal Rate Recommendations")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Based on \(viewModel.daysAnalyzed) days of historical data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if viewModel.isAnalyzing {
                        ProgressView("Analyzing...")
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Analysis period picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Analysis Period")
                        .font(.headline)

                    Picker("Days", selection: $viewModel.selectedDays) {
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)

                // Info box
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("How it works")
                            .font(.headline)
                    }

                    Text("Recommendations are based on periods where:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("No active carbs (>1g) during the period")
                        bulletPoint("No recent lows (<4.0 mmol/L) within 8 hours before")
                        bulletPoint("Low active insulin (IOB <0.5 U) at period start")
                        bulletPoint("Glucose within 4.0-13.0 mmol/L for 2+ hours")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)

                // Recommendations
                if !viewModel.recommendations.isEmpty {
                    VStack(spacing: 16) {
                        ForEach(viewModel.recommendations) { recommendation in
                            if recommendation.sampleCount > 0 {
                                NavigationLink(destination: PeriodsListView(
                                    recommendation: recommendation,
                                    viewModel: viewModel
                                )) {
                                    recommendationCard(recommendation)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                recommendationCard(recommendation)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else if !viewModel.isAnalyzing {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text("No recommendations available")
                            .font(.headline)

                        Text("Not enough qualifying data periods found. Try again after collecting more data with no active carbs and glucose in range.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                // Debug: Show rejected periods
                if !viewModel.rejectedPeriods.isEmpty {
                    Divider()
                        .padding(.vertical)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Debug: Rejected Periods (\(viewModel.rejectedPeriods.count))")
                            .font(.headline)

                        let periodsToShow = showAllRejectedPeriods ? viewModel.rejectedPeriods : Array(viewModel.rejectedPeriods.prefix(10))

                        ForEach(periodsToShow) { rejected in
                            NavigationLink(destination: RejectedPeriodDetailView(
                                rejected: rejected,
                                viewModel: viewModel
                            )) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(formatPeriodTime(rejected.measurementStart))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text("Duration: \(String(format: "%.1f", rejected.durationHours)) hours")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Rejected: \(rejected.rejectionSummary)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if viewModel.rejectedPeriods.count > 10 {
                            Button(action: {
                                showAllRejectedPeriods.toggle()
                            }) {
                                HStack {
                                    Image(systemName: showAllRejectedPeriods ? "chevron.up" : "chevron.down")
                                    Text(showAllRejectedPeriods ? "Show less" : "Show \(viewModel.rejectedPeriods.count - 10) more")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button("Refresh") {
            viewModel.refreshRecommendations()
        })
        .onAppear {
            if viewModel.recommendations.isEmpty {
                viewModel.refreshRecommendations()
            }
        }
    }

    private func formatPeriodTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    private func recommendationCard(_ recommendation: BasalRateRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time header
            HStack {
                Text(timeRangeString(for: recommendation))
                    .font(.headline)

                Spacer()

                if recommendation.sampleCount > 0 {
                    confidenceBadge(recommendation.confidence)
                }
            }

            Divider()

            // Show "Insufficient Data" message if no samples
            if recommendation.sampleCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)

                    Text("Insufficient Data")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("No qualifying analysis periods found for this time range in the last \(viewModel.daysAnalyzed) days.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Current Basal: \(String(format: "%.2f U/hr", recommendation.currentBasalRate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {

            // Glucose trend
            VStack(alignment: .leading, spacing: 4) {
                Text("Glucose Trend")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    trendIcon(for: recommendation.glucoseTrend)
                    Text(glucoseTrendString(recommendation.glucoseTrend))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            Divider()

            // Current vs Recommended
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Basal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f U/hr", recommendation.currentBasalRate))
                        .font(.title3)
                        .fontWeight(.medium)
                }

                Image(systemName: "arrow.right")
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f U/hr", recommendation.recommendedBasalRate))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(changeColor(for: recommendation.changeAmount))
                }
            }

            // Change summary
            if abs(recommendation.changeAmount) > 0.01 {
                HStack {
                    Image(systemName: recommendation.changeAmount > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(changeColor(for: recommendation.changeAmount))

                    Text(changeSummary(for: recommendation))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(changeColor(for: recommendation.changeAmount).opacity(0.1))
                .cornerRadius(8)
            }

            // Sample count
            Text("\(recommendation.sampleCount) qualifying period\(recommendation.sampleCount == 1 ? "" : "s") found")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func timeRangeString(for recommendation: BasalRateRecommendation) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        return "\(formatter.string(from: recommendation.startDate)) - \(formatter.string(from: recommendation.endDate))"
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color
        let text: String

        if confidence >= 0.7 {
            color = .green
            text = "High"
        } else if confidence >= 0.4 {
            color = .orange
            text = "Medium"
        } else {
            color = .red
            text = "Low"
        }

        return Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func trendIcon(for trend: Double) -> some View {
        let icon: String
        let color: Color

        if abs(trend) < 5 {
            icon = "arrow.right"
            color = .green
        } else if trend > 0 {
            icon = "arrow.up"
            color = .red
        } else {
            icon = "arrow.down"
            color = .blue
        }

        return Image(systemName: icon)
            .foregroundColor(color)
    }

    private func glucoseTrendString(_ trend: Double) -> String {
        // Trend is stored as mg/dL per hour, convert to user's preferred unit
        let trendValue: Double
        let unitString: String
        let decimalPlaces: Int

        if displayGlucosePreference.unit == .millimolesPerLiter {
            // Convert mg/dL to mmol/L (divide by 18.018)
            trendValue = trend / 18.018
            unitString = "mmol/L/hr"
            decimalPlaces = 2
        } else {
            trendValue = trend
            unitString = "mg/dL/hr"
            decimalPlaces = 1
        }

        return String(format: "%+.\(decimalPlaces)f \(unitString)", trendValue)
    }

    private func glucoseString(_ quantity: HKQuantity) -> String {
        let value = displayGlucosePreference.unit == .millimolesPerLiter ?
            quantity.doubleValue(for: .millimolesPerLiter) :
            quantity.doubleValue(for: .milligramsPerDeciliter)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = displayGlucosePreference.unit == .millimolesPerLiter ? 1 : 0

        return formatter.string(from: NSNumber(value: value)) ?? "-"
    }

    private func changeColor(for change: Double) -> Color {
        if abs(change) < 0.01 {
            return .green
        } else if change > 0 {
            return .orange
        } else {
            return .blue
        }
    }

    private func changeSummary(for recommendation: BasalRateRecommendation) -> String {
        let action = recommendation.changeAmount > 0 ? "Increase" : "Decrease"
        let amount = abs(recommendation.changeAmount)
        let percentage = abs(recommendation.changePercentage)

        return String(format: "%@ by %.2f U/hr (%.0f%%)", action, amount, percentage)
    }
}

// MARK: - Rejected Period Detail View

struct RejectedPeriodDetailView: View {
    let rejected: RejectedPeriod
    let viewModel: BasalRateRecommendationsViewModel

    @StateObject private var detailViewModel: RejectedPeriodDetailViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    init(rejected: RejectedPeriod, viewModel: BasalRateRecommendationsViewModel) {
        self.rejected = rejected
        self.viewModel = viewModel
        let vm = RejectedPeriodDetailViewModel(
            rejected: rejected,
            glucoseStore: viewModel.glucoseStore,
            carbStore: viewModel.carbStore,
            doseStore: viewModel.doseStore
        )
        _detailViewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rejected Period")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(formatPeriodRange(rejected.measurementStart, rejected.measurementEnd))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Includes 8 hours before and 3 hours after for context")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Rejection reasons
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why This Period Was Rejected")
                        .font(.headline)

                    ForEach(rejected.rejectionReasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(reason)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // Period summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Period Summary")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Duration", value: String(format: "%.1f hours", rejected.durationHours))
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                if detailViewModel.isLoading {
                    ProgressView("Loading charts...")
                        .padding()
                } else {
                    // Show the same charts as qualified periods
                    if !detailViewModel.glucoseSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Glucose")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: PeriodDetailChartsManager.ChartIndex.glucose.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 200)
                        }
                    }

                    if !detailViewModel.iobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Insulin (IOB)")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: PeriodDetailChartsManager.ChartIndex.iob.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    if !detailViewModel.cobValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Carbs (COB)")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: PeriodDetailChartsManager.ChartIndex.cob.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

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

                    if !detailViewModel.doseEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insulin Doses")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: PeriodDetailChartsManager.ChartIndex.dose.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Rejected Period Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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

// MARK: - Rejected Period Detail View Model

class RejectedPeriodDetailViewModel: ObservableObject {
    @Published var glucoseSamples: [StoredGlucoseSample] = []
    @Published var doseEntries: [DoseEntry] = []
    @Published var basalDoses: [DoseEntry] = []
    @Published var iobValues: [InsulinValue] = []
    @Published var cobValues: [CarbValue] = []
    @Published var isLoading = false

    private let rejected: RejectedPeriod
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    var glucoseUnit: HKUnit = .milligramsPerDeciliter

    var displayPeriod: (start: Date, end: Date) {
        let extendedStart = rejected.measurementStart.addingTimeInterval(-8 * 3600)
        let extendedEnd = rejected.measurementEnd.addingTimeInterval(3 * 3600)
        return (extendedStart, extendedEnd)
    }

    var measurementPeriod: (start: Date, end: Date) {
        return (rejected.measurementStart, rejected.measurementEnd)
    }

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

    init(rejected: RejectedPeriod, glucoseStore: GlucoseStoreProtocol, carbStore: CarbStoreProtocol, doseStore: DoseStoreProtocol) {
        self.rejected = rejected
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
    }

    func loadData() {
        isLoading = true

        let start = displayPeriod.start
        let end = displayPeriod.end

        let group = DispatchGroup()

        // Load glucose
        group.enter()
        glucoseStore.getGlucoseSamples(start: start, end: end) { result in
            if case .success(let samples) = result {
                DispatchQueue.main.async {
                    self.glucoseSamples = samples
                }
            }
            group.leave()
        }

        // Load COB
        group.enter()
        carbStore.getCarbsOnBoardValues(start: start, end: end, effectVelocities: nil) { result in
            if case .success(let values) = result {
                DispatchQueue.main.async {
                    self.cobValues = values
                }
            }
            group.leave()
        }

        // Load doses
        group.enter()
        doseStore.getNormalizedDoseEntries(start: start, end: end) { result in
            if case .success(let doses) = result {
                DispatchQueue.main.async {
                    self.basalDoses = doses.filter { $0.type == .basal || $0.type == .tempBasal || $0.type == .suspend }
                    self.doseEntries = doses.filter { $0.type != .basal }
                }
            }
            group.leave()
        }

        // Load IOB
        group.enter()
        doseStore.getInsulinOnBoardValues(start: start, end: end, basalDosingEnd: nil) { result in
            if case .success(let iobValues) = result {
                DispatchQueue.main.async {
                    self.iobValues = iobValues
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
        let start = displayPeriod.start
        let end = displayPeriod.end

        chartsManager.startDate = start
        chartsManager.updateEndDate(end)
        chartsManager.glucose.glucoseUnit = glucoseUnit

        if !glucoseSamples.isEmpty {
            let glucoseValues = glucoseSamples.map { SimpleGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
            chartsManager.setGlucoseValues(glucoseValues)
        }

        if !iobValues.isEmpty {
            chartsManager.setIOBValues(iobValues)
        }

        if !doseEntries.isEmpty {
            chartsManager.setDoseEntries(doseEntries)
        }

        if !cobValues.isEmpty {
            chartsManager.setCOBValues(cobValues)
        }

        if !basalDoses.isEmpty {
            chartsManager.setBasalDoses(basalDoses)
        }
    }
}
