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
    @Published var isAnalyzing: Bool = false
    @Published var selectedDays: Int = 30 {
        didSet {
            // Auto-refresh when selection changes
            refreshRecommendations()
        }
    }

    var daysAnalyzed: Int { selectedDays }

    private let recommendationManager: SettingsRecommendationManager

    init(
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        doseStore: DoseStoreProtocol,
        settings: @escaping () -> LoopSettings
    ) {
        self.recommendationManager = SettingsRecommendationManager(
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            doseStore: doseStore,
            settings: settings
        )
    }

    func refreshRecommendations() {
        isAnalyzing = true
        recommendations = []

        recommendationManager.generateBasalRateRecommendations(daysToAnalyze: selectedDays) { [weak self] newRecommendations in
            DispatchQueue.main.async {
                self?.recommendations = newRecommendations
                self?.isAnalyzing = false
            }
        }
    }
}
