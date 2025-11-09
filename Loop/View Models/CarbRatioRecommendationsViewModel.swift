//
//  CarbRatioRecommendationsViewModel.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import LoopCore

public class CarbRatioRecommendationsViewModel: ObservableObject {
    @Published var recommendations: [CarbRatioRecommendation] = []
    @Published var rejectedMeals: [RejectedMeal] = []
    @Published var isAnalyzing: Bool = false
    @Published var selectedDays: Int {
        didSet {
            // Save to UserDefaults
            UserDefaults.standard.set(selectedDays, forKey: "CarbRatioAnalysisPeriodDays")
            // Auto-refresh when selection changes
            refreshRecommendations()
        }
    }

    var daysAnalyzed: Int { selectedDays }

    private let recommendationManager: SettingsRecommendationManager

    // For detail view
    let glucoseStore: GlucoseStoreProtocol
    let carbStore: CarbStoreProtocol
    let doseStore: DoseStoreProtocol

    init(
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        doseStore: DoseStoreProtocol,
        settings: @escaping () -> LoopSettings
    ) {
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.recommendationManager = SettingsRecommendationManager(
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            doseStore: doseStore,
            settings: settings
        )

        // Load saved preference or default to 30 days
        let savedDays = UserDefaults.standard.integer(forKey: "CarbRatioAnalysisPeriodDays")
        self.selectedDays = savedDays > 0 ? savedDays : 30
    }

    func refreshRecommendations() {
        isAnalyzing = true
        recommendations = []
        rejectedMeals = []

        recommendationManager.generateCarbRatioRecommendations(daysToAnalyze: selectedDays) { [weak self] newRecommendations, newRejectedMeals in
            DispatchQueue.main.async {
                self?.recommendations = newRecommendations
                // Sort rejected meals in reverse chronological order (latest first)
                self?.rejectedMeals = newRejectedMeals.sorted { $0.carbEntryTime > $1.carbEntryTime }
                self?.isAnalyzing = false
            }
        }
    }
}
