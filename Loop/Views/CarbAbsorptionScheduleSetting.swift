//
//  CarbAbsorptionScheduleSetting.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import LoopCore

extension TherapySettingsView.AdditionalScheduleSetting {
    /// The carb absorption time schedule as a card in Therapy Settings, edited like the other schedules.
    static func carbAbsorptionSchedule(defaults: UserDefaults = .standard) -> Self {
        let step = TimeInterval.minutes(30)
        let selectableHours = stride(from: LoopConstants.minCarbAbsorptionTime,
                                     through: LoopConstants.maxCarbAbsorptionTime,
                                     by: step).map { $0 / .hours(1) }
        return Self(
            title: String(localized: "Carb Absorption Times", comment: "Title for carb absorption time schedule view"),
            descriptiveText: String(localized: "Default absorption time for new carb entries, by time of day of the meal. Favorite foods, 🍭, 🍕 and times you change yourself are kept."),
            unit: .hour(),
            selectableValues: selectableHours,
            defaultFirstValue: LoopCoreConstants.defaultCarbAbsorptionTimes.medium / .hours(1),
            schedule: defaults.carbAbsorptionTimeSchedule.hourSchedule,
            onSave: { defaults.carbAbsorptionTimeSchedule = CarbAbsorptionTimeSchedule(hourSchedule: $0) }
        )
    }
}
