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
    /// Every half hour within Loop's absorption time limits.
    static let carbAbsorptionSelectableHours = stride(from: LoopConstants.minCarbAbsorptionTime,
                                                      through: LoopConstants.maxCarbAbsorptionTime,
                                                      by: .minutes(30)).map { $0 / .hours(1) }

    /// Hours as hours and minutes, e.g. "2 hr, 30 min", in the style of the carb entry screen.
    static func carbAbsorptionHoursString(_ hours: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: hours * .hours(1)) ?? ""
    }

    /// The carb absorption time schedule as a card in Therapy Settings, edited like the other schedules.
    static func carbAbsorptionSchedule(defaults: UserDefaults = .standard) -> Self {
        Self(
            title: String(localized: "Carb Absorption Times", comment: "Title for carb absorption time schedule view"),
            descriptiveText: String(localized: "Default absorption time for new carb entries, by time of day of the meal. Favorite foods, 🍭, 🍕 and times you change yourself are kept."),
            unit: .hour(),
            selectableValues: carbAbsorptionSelectableHours,
            defaultFirstValue: LoopCoreConstants.defaultCarbAbsorptionTimes.medium / .hours(1),
            schedule: defaults.carbAbsorptionTimeSchedule.hourSchedule,
            valueFormatter: carbAbsorptionHoursString,
            onSave: { defaults.carbAbsorptionTimeSchedule = CarbAbsorptionTimeSchedule(hourSchedule: $0) }
        )
    }
}
