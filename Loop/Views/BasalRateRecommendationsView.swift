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

public struct BasalRateRecommendationsView: View {
    @StateObject private var viewModel: BasalRateRecommendationsViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

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

    private func recommendationCard(_ recommendation: BasalRateRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time header
            HStack {
                Text(timeRangeString(for: recommendation.hourOfDay))
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

    private func timeRangeString(for hour: Int) -> String {
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "HH:mm"

        let calendar = Calendar.current
        let startDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        let endDate = calendar.date(byAdding: .hour, value: 4, to: startDate) ?? Date()

        return "\(startFormatter.string(from: startDate)) - \(startFormatter.string(from: endDate))"
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
