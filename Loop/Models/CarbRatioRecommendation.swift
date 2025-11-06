//
//  CarbRatioRecommendation.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

/// Represents a carb ratio (I:C) recommendation based on meal analysis
struct CarbRatioRecommendation: Identifiable {
    let id = UUID()

    /// Time of day (hour) this recommendation applies to
    let hourOfDay: Int

    /// Start time for display
    let startDate: Date

    /// End time for display
    let endDate: Date

    /// Current carb ratio setting (grams per unit)
    let currentCarbRatio: Double

    /// Recommended carb ratio (grams per unit)
    let recommendedCarbRatio: Double

    /// Average glucose change during analysis periods (mg/dL)
    let averageGlucoseChange: Double

    /// Average starting glucose (mg/dL)
    let averageStartGlucose: HKQuantity

    /// Average ending glucose (mg/dL)
    let averageEndGlucose: HKQuantity

    /// Confidence level (0.0 - 1.0)
    let confidence: Double

    /// Number of qualifying meal periods found
    let mealCount: Int

    /// Actual qualifying meal windows used for this recommendation
    let qualifyingMeals: [CarbRatioAnalysisWindow]

    var changeAmount: Double {
        return recommendedCarbRatio - currentCarbRatio
    }

    var changePercentage: Double {
        guard currentCarbRatio > 0 else { return 0 }
        return (changeAmount / currentCarbRatio) * 100
    }

    var recommendation: String {
        // If change is less than 1g, ratio is appropriate
        if abs(changeAmount) < 1.0 {
            return "Carb ratio appears appropriate"
        } else if averageGlucoseChange > 0 {
            return "Consider decreasing carb ratio (more insulin per carb)"
        } else {
            return "Consider increasing carb ratio (less insulin per carb)"
        }
    }
}

/// Analysis window representing a meal period that meets criteria for carb ratio testing
struct CarbRatioAnalysisWindow {
    /// Start of the carb entry
    let carbEntryTime: Date

    /// End of the observation period (typically 4-5 hours after meal)
    let observationEnd: Date

    /// The carb entry being analyzed
    let carbEntry: StoredCarbEntry

    /// Meal bolus given for this carb entry (excluding correction)
    let mealBolus: Double

    /// Correction bolus component (if any)
    let correctionBolus: Double

    /// Starting glucose value
    let startGlucose: StoredGlucoseSample

    /// Ending glucose value
    let endGlucose: StoredGlucoseSample

    /// Hour of day (0-23) for grouping
    var hourOfDay: Int {
        Calendar.current.component(.hour, from: carbEntryTime)
    }

    /// Glucose change (mg/dL)
    var glucoseChange: Double {
        endGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) -
        startGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)
    }

    /// Carb amount in grams
    var carbAmount: Double {
        carbEntry.quantity.doubleValue(for: .gram())
    }

    /// Observed carb ratio (grams per unit of meal insulin)
    var observedCarbRatio: Double {
        guard mealBolus > 0 else { return 0 }
        return carbAmount / mealBolus
    }
}

/// Debug information about why a meal was rejected or accepted
struct MealAnalysisDebug: Identifiable {
    let id = UUID()
    let carbEntryTime: Date
    let carbAmount: Double
    let mealBolus: Double
    let isValid: Bool
    let rejectionReasons: [String]
}

/// Debug results from carb ratio analysis
struct CarbRatioAnalysisDebugInfo {
    let analyzedMeals: [MealAnalysisDebug]
    let totalMealsChecked: Int
    let validMealsFound: Int
    let totalCarbEntries: Int
    let analysisPeriod: (start: Date, end: Date)
}
