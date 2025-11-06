//
//  BasalRateRecommendation.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

/// Represents a basal rate recommendation based on historical data analysis
struct BasalRateRecommendation: Identifiable {
    let id = UUID()

    /// Start time of the analysis window
    let startDate: Date

    /// End time of the analysis window
    let endDate: Date

    /// Time of day (hour) this recommendation applies to
    let hourOfDay: Int

    /// Current basal rate during this period (units/hour)
    let currentBasalRate: Double

    /// Recommended basal rate (units/hour)
    let recommendedBasalRate: Double

    /// Average glucose trend during analysis (mg/dL per hour)
    let glucoseTrend: Double

    /// Starting glucose value
    let startGlucose: HKQuantity

    /// Ending glucose value
    let endGlucose: HKQuantity

    /// Confidence level (0.0 - 1.0)
    let confidence: Double

    /// Number of similar periods found
    let sampleCount: Int

    /// Actual qualifying windows used for this recommendation
    let qualifyingWindows: [BasalAnalysisWindow]

    var changeAmount: Double {
        return recommendedBasalRate - currentBasalRate
    }

    var changePercentage: Double {
        guard currentBasalRate > 0 else { return 0 }
        return (changeAmount / currentBasalRate) * 100
    }

    var recommendation: String {
        // If change is less than minimum step size (0.05 U/hr), basal is appropriate
        if abs(changeAmount) < 0.05 {
            return "Basal rate appears appropriate"
        } else if glucoseTrend > 0 {
            return "Consider increasing basal rate"
        } else {
            return "Consider decreasing basal rate"
        }
    }
}

/// Analysis window that meets criteria for basal testing
struct BasalAnalysisWindow {
    /// Start of the measurement period
    let measurementStart: Date

    /// End of the measurement period
    let measurementEnd: Date

    /// Start of the carb-free period (3 hours before measurement)
    let carbFreeStart: Date

    /// Active doses (boluses, temp basals) affecting this period
    let activeDoses: [DoseEntry]

    /// Hour of day (0-23) for grouping
    var hourOfDay: Int {
        Calendar.current.component(.hour, from: measurementStart)
    }

    /// Duration of measurement period in hours
    var duration: TimeInterval {
        return measurementEnd.timeIntervalSince(measurementStart)
    }
}

/// Debug information about why a period was rejected or accepted
struct PeriodAnalysisDebug: Identifiable {
    let id = UUID()
    let measurementStart: Date
    let measurementEnd: Date
    let duration: TimeInterval
    let isValid: Bool
    let rejectionReasons: [String]

    var durationHours: Double {
        duration / .hours(1)
    }
}

/// Debug results from basal rate analysis
struct BasalAnalysisDebugInfo {
    let analyzedPeriods: [PeriodAnalysisDebug]
    let totalPeriodsChecked: Int
    let validPeriodsFound: Int
    let totalGlucoseSamples: Int
    let glucoseDateRange: (start: Date?, end: Date?)
    let analysisPeriod: (start: Date, end: Date)
}
