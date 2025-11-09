//
//  MealDetailView.swift
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

struct MealsListView: View {
    let recommendation: CarbRatioRecommendation
    let viewModel: CarbRatioRecommendationsViewModel

    var body: some View {
        List {
            Section(header: Text("Qualifying Meals (\(recommendation.qualifyingMeals.count))")) {
                ForEach(recommendation.qualifyingMeals.indices, id: \.self) { index in
                    let meal = recommendation.qualifyingMeals[index]
                    NavigationLink(destination: MealDetailView(
                        meal: meal,
                        viewModel: viewModel
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatMealTime(meal.carbEntryTime))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            HStack {
                                Text("Carbs: \(String(format: "%.0fg", meal.carbAmount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("Insulin: \(String(format: "%.1fU", meal.mealBolus))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("Ratio: \(String(format: "%.1fg/U", meal.observedCarbRatio))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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

    private func formatMealTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MealDetailView: View {
    let meal: CarbRatioAnalysisWindow
    let viewModel: CarbRatioRecommendationsViewModel

    @StateObject private var detailViewModel: MealDetailViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    init(meal: CarbRatioAnalysisWindow, viewModel: CarbRatioRecommendationsViewModel) {
        self.meal = meal
        self.viewModel = viewModel
        let vm = MealDetailViewModel(
            meal: meal,
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
                    Text("Meal Details")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(formatMealTime(meal.carbEntryTime))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Includes 8 hours before and 3 hours after for context")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Meal summary card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meal Summary")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Carbs", value: String(format: "%.0f g", meal.carbAmount))
                            DetailRow(label: "Insulin", value: String(format: "%.2f U", meal.mealBolus))
                            DetailRow(label: "Observed Ratio", value: String(format: "%.1f g/U", meal.observedCarbRatio))
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Start Glucose", value: formatGlucose(meal.startGlucose.quantity))
                            DetailRow(label: "End Glucose", value: formatGlucose(meal.endGlucose.quantity))
                            DetailRow(label: "Change", value: formatGlucoseChange(meal.glucoseChange))
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
                    // Glucose chart
                    if !detailViewModel.glucoseSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Glucose")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: MealDetailChartsManager.ChartIndex.glucose.rawValue,
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
                                chartIndex: MealDetailChartsManager.ChartIndex.iob.rawValue,
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
                                chartIndex: MealDetailChartsManager.ChartIndex.cob.rawValue,
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
                                chartIndex: MealDetailChartsManager.ChartIndex.basalRate.rawValue,
                                measurementPeriod: detailViewModel.measurementPeriod
                            )
                            .frame(height: 150)
                        }
                    }

                    // Dose chart
                    if !detailViewModel.doseEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insulin Doses")
                                .font(.headline)
                                .padding(.horizontal)

                            LoopChartView(
                                chartManager: detailViewModel.chartsManager,
                                chartIndex: MealDetailChartsManager.ChartIndex.dose.rawValue,
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
                       detailViewModel.doseEntries.isEmpty {
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
        .navigationTitle(formatMealTime(meal.carbEntryTime))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            detailViewModel.glucoseUnit = displayGlucosePreference.unit
            detailViewModel.loadData()
        }
    }

    private func formatMealTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatGlucose(_ quantity: HKQuantity) -> String {
        let value = displayGlucosePreference.unit == .millimolesPerLiter ?
            quantity.doubleValue(for: .millimolesPerLiter) :
            quantity.doubleValue(for: .milligramsPerDeciliter)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = displayGlucosePreference.unit == .millimolesPerLiter ? 1 : 0

        let unitString = displayGlucosePreference.unit == .millimolesPerLiter ? "mmol/L" : "mg/dL"
        return "\(formatter.string(from: NSNumber(value: value)) ?? "-") \(unitString)"
    }

    private func formatGlucoseChange(_ change: Double) -> String {
        let changeValue: Double
        let unitString: String

        if displayGlucosePreference.unit == .millimolesPerLiter {
            changeValue = change / 18.018
            unitString = "mmol/L"
        } else {
            changeValue = change
            unitString = "mg/dL"
        }

        return String(format: "%+.1f \(unitString)", changeValue)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

class MealDetailViewModel: ObservableObject {
    @Published var glucoseSamples: [StoredGlucoseSample] = []
    @Published var doseEntries: [DoseEntry] = []
    @Published var basalDoses: [DoseEntry] = []
    @Published var iobValues: [InsulinValue] = []
    @Published var cobValues: [CarbValue] = []
    @Published var isLoading = false

    private let meal: CarbRatioAnalysisWindow
    private let glucoseStore: GlucoseStoreProtocol
    private let carbStore: CarbStoreProtocol
    private let doseStore: DoseStoreProtocol
    var glucoseUnit: HKUnit = .milligramsPerDeciliter

    var displayPeriod: (start: Date, end: Date) {
        let extendedStart = meal.carbEntryTime.addingTimeInterval(-8 * 3600)
        let extendedEnd = meal.observationEnd.addingTimeInterval(3 * 3600)
        return (extendedStart, extendedEnd)
    }

    var measurementPeriod: (start: Date, end: Date) {
        return (meal.carbEntryTime, meal.observationEnd)
    }

    lazy var chartsManager: MealDetailChartsManager = {
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
        return MealDetailChartsManager(colors: colors, settings: settings, traitCollection: .current)
    }()

    init(meal: CarbRatioAnalysisWindow, glucoseStore: GlucoseStoreProtocol, carbStore: CarbStoreProtocol, doseStore: DoseStoreProtocol) {
        self.meal = meal
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
    }

    func loadData() {
        isLoading = true

        // Load data for extended period (8 hours before and 3 hours after)
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
                    // Separate basal doses from other insulin doses
                    self.basalDoses = doses.filter { $0.type == .basal || $0.type == .tempBasal || $0.type == .suspend }
                    self.doseEntries = doses.filter { $0.type != .basal }
                }
            }
            group.leave()
        }

        // Load IOB using Loop's insulin model
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
        // Use extended display period for chart range
        let start = displayPeriod.start
        let end = displayPeriod.end

        // Update date range - set maxEndDate first to prevent rounding up
        chartsManager.maxEndDate = end
        chartsManager.startDate = start
        chartsManager.updateEndDate(end)

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
        if !doseEntries.isEmpty {
            chartsManager.setDoseEntries(doseEntries)
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
