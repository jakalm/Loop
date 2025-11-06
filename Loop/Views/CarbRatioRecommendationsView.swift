//
//  CarbRatioRecommendationsView.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI

public struct CarbRatioRecommendationsView: View {
    @StateObject private var viewModel: CarbRatioRecommendationsViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    public init(viewModel: CarbRatioRecommendationsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Carb Ratio Recommendations")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Based on \(viewModel.daysAnalyzed) days of meal data")
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

                    Text("Recommendations are based on meals where:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Minimal active carbs (<1g COB) at meal time")
                        bulletPoint("Single isolated meal (no other carbs during observation)")
                        bulletPoint("No recent lows (<4.0 mmol/L) within 8 hours")
                        bulletPoint("Low active insulin (IOB <0.5 U) at meal start")
                        bulletPoint("No correction boluses during observation")
                        bulletPoint("Glucose within 4.0-13.0 mmol/L for 2+ hours")
                        bulletPoint("At least 10g carbs for reliable analysis")
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
                            if recommendation.mealCount > 0 {
                                NavigationLink(destination: MealsListView(
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
                        Image(systemName: "fork.knife")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text("No recommendations available")
                            .font(.headline)

                        Text("Not enough qualifying meals found. Try again after collecting more isolated meal data with proper bolusing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
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

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    private func recommendationCard(_ recommendation: CarbRatioRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time header
            HStack {
                Text(timeRangeString(for: recommendation))
                    .font(.headline)

                Spacer()

                if recommendation.mealCount > 0 {
                    confidenceBadge(recommendation.confidence)
                }
            }

            Divider()

            // Show "Insufficient Data" message if no meals
            if recommendation.mealCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)

                    Text("Insufficient Data")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("No qualifying meals found for this time range in the last \(viewModel.daysAnalyzed) days.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Current Ratio: \(String(format: "%.1f g/U", recommendation.currentCarbRatio))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Glucose change
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Glucose Change")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        trendIcon(for: recommendation.averageGlucoseChange)
                        Text(glucoseChangeString(recommendation.averageGlucoseChange))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                Divider()

                // Current vs Recommended
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Ratio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f g/U", recommendation.currentCarbRatio))
                            .font(.title3)
                            .fontWeight(.medium)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f g/U", recommendation.recommendedCarbRatio))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(changeColor(for: recommendation.changeAmount))
                    }
                }

                // Change summary
                if abs(recommendation.changeAmount) > 0.5 {
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

                // Meal count
                Text("\(recommendation.mealCount) qualifying meal\(recommendation.mealCount == 1 ? "" : "s") analyzed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func timeRangeString(for recommendation: CarbRatioRecommendation) -> String {
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

    private func trendIcon(for change: Double) -> some View {
        let icon: String
        let color: Color

        if abs(change) < 10 {
            icon = "arrow.right"
            color = .green
        } else if change > 0 {
            icon = "arrow.up"
            color = .red
        } else {
            icon = "arrow.down"
            color = .blue
        }

        return Image(systemName: icon)
            .foregroundColor(color)
    }

    private func glucoseChangeString(_ change: Double) -> String {
        // Change is stored as mg/dL, convert to user's preferred unit
        let changeValue: Double
        let unitString: String
        let decimalPlaces: Int

        if displayGlucosePreference.unit == .millimolesPerLiter {
            // Convert mg/dL to mmol/L (divide by 18.018)
            changeValue = change / 18.018
            unitString = "mmol/L"
            decimalPlaces = 1
        } else {
            changeValue = change
            unitString = "mg/dL"
            decimalPlaces = 0
        }

        return String(format: "%+.\(decimalPlaces)f \(unitString)", changeValue)
    }

    private func changeColor(for change: Double) -> Color {
        if abs(change) < 0.5 {
            return .green
        } else if change > 0 {
            // Positive change = higher ratio = less insulin per carb
            return .blue
        } else {
            // Negative change = lower ratio = more insulin per carb
            return .orange
        }
    }

    private func changeSummary(for recommendation: CarbRatioRecommendation) -> String {
        let action: String
        let interpretation: String

        if recommendation.changeAmount > 0 {
            action = "Increase"
            interpretation = "less insulin per carb"
        } else {
            action = "Decrease"
            interpretation = "more insulin per carb"
        }

        let amount = abs(recommendation.changeAmount)
        let percentage = abs(recommendation.changePercentage)

        return String(format: "%@ by %.1f g/U (%.0f%%) - %@", action, amount, percentage, interpretation)
    }
}
