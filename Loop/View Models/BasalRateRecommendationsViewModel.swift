//
//  BasalRateRecommendationsViewModel.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import LoopCore

public class BasalRateRecommendationsViewModel: ObservableObject {
    @Published var recommendations: [BasalRateRecommendation] = []
    @Published var rejectedPeriods: [RejectedPeriod] = []
    @Published var isAnalyzing: Bool = false
    @Published var selectedDays: Int {
        didSet {
            // Save to UserDefaults
            UserDefaults.standard.set(selectedDays, forKey: "BasalRateAnalysisPeriodDays")
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

        // Load saved preference or default to 14 days
        let savedDays = UserDefaults.standard.integer(forKey: "BasalRateAnalysisPeriodDays")
        self.selectedDays = savedDays > 0 ? savedDays : 14
    }

    func refreshRecommendations() {
        isAnalyzing = true
        recommendations = []
        rejectedPeriods = []

        recommendationManager.generateBasalRateRecommendations(daysToAnalyze: selectedDays) { [weak self] newRecommendations, newRejectedPeriods in
            DispatchQueue.main.async {
                self?.recommendations = newRecommendations
                // Sort rejected periods in reverse chronological order (latest first)
                self?.rejectedPeriods = newRejectedPeriods.sorted { $0.measurementStart > $1.measurementStart }
                self?.isAnalyzing = false
            }
        }
    }
}
