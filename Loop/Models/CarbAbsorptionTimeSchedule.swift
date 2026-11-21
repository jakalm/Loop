//
//  CarbAbsorptionTimeSchedule.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Default carb absorption time by local time of day, used as the medium (🌮) absorption time for new carb entries.
struct CarbAbsorptionTimeSchedule: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        /// Seconds since local midnight.
        var startTime: TimeInterval
        var absorptionTime: TimeInterval
    }

    var isEnabled: Bool
    var items: [Item]

    static let suggested = CarbAbsorptionTimeSchedule(
        isEnabled: false,
        items: [
            Item(startTime: .hours(4), absorptionTime: .hours(2.5)),
            Item(startTime: .hours(10), absorptionTime: .hours(4.5)),
            Item(startTime: .hours(15), absorptionTime: .hours(4.5)),
            Item(startTime: .hours(21), absorptionTime: .hours(5)),
        ]
    )

    var sortedItems: [Item] {
        items.sorted { $0.startTime < $1.startTime }
    }

    /// The scheduled absorption time for a meal at `date`, or nil when the schedule is off or empty.
    /// Times before the first start belong to the last item, so the schedule wraps around midnight.
    func absorptionTime(at date: Date, calendar: Calendar = .current) -> TimeInterval? {
        let sorted = sortedItems
        guard isEnabled, let last = sorted.last else {
            return nil
        }
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let secondsSinceMidnight = TimeInterval((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
        let item = sorted.last { $0.startTime <= secondsSinceMidnight } ?? last
        return min(max(item.absorptionTime, LoopConstants.minCarbAbsorptionTime), LoopConstants.maxCarbAbsorptionTime)
    }

    /// `base` with the medium absorption time replaced by the scheduled one for a meal at `date`.
    func defaultAbsorptionTimes(base: CarbStore.DefaultAbsorptionTimes, at date: Date, calendar: Calendar = .current) -> CarbStore.DefaultAbsorptionTimes {
        guard let scheduled = absorptionTime(at: date, calendar: calendar) else {
            return base
        }
        return (fast: base.fast, medium: scheduled, slow: base.slow)
    }

    /// The absorption time to switch to when the meal time moves, or nil to keep the current one.
    /// Only follows the schedule while the entry still uses the previous medium default untouched.
    static func absorptionTimeAfterMealTimeChange(current: TimeInterval,
                                                   previousMedium: TimeInterval,
                                                   newMedium: TimeInterval,
                                                   wasEdited: Bool,
                                                   usesCustomFoodType: Bool) -> TimeInterval? {
        guard !wasEdited, !usesCustomFoodType, current == previousMedium, newMedium != current else {
            return nil
        }
        return newMedium
    }
}
