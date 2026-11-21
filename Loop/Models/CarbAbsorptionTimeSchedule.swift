//
//  CarbAbsorptionTimeSchedule.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore

/// Default carb absorption time by local time of day, used as the medium (🌮) absorption time for new carb entries.
struct CarbAbsorptionTimeSchedule: Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        /// Seconds since local midnight.
        var startTime: TimeInterval
        var absorptionTime: TimeInterval
    }

    var items: [Item]

    /// Loop's fixed medium absorption time all day.
    static let standard = CarbAbsorptionTimeSchedule(items: [
        Item(startTime: 0, absorptionTime: LoopCoreConstants.defaultCarbAbsorptionTimes.medium)
    ])

    var sortedItems: [Item] {
        items.sorted { $0.startTime < $1.startTime }
    }

    /// The scheduled absorption time for a meal at `date`, or nil when the schedule is empty.
    /// Times before the first start belong to the last item, so the schedule wraps around midnight.
    func absorptionTime(at date: Date, calendar: Calendar = .current) -> TimeInterval? {
        let sorted = sortedItems
        guard let last = sorted.last else {
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

extension CarbAbsorptionTimeSchedule: Codable {
    private enum CodingKeys: String, CodingKey {
        case items
        case isEnabled // only in schedules saved by an earlier version, where it could be turned off
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([Item].self, forKey: .items)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.items = isEnabled && !items.isEmpty ? items : Self.standard.items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

extension CarbAbsorptionTimeSchedule {
    /// The schedule in hours for the schedule editors, which start at midnight.
    var hourSchedule: DailyQuantitySchedule<Double> {
        let sorted = sortedItems.isEmpty ? Self.standard.items : sortedItems
        var items = sorted.map { RepeatingScheduleValue(startTime: $0.startTime, value: $0.absorptionTime / .hours(1)) }
        if items[0].startTime > 0, let last = items.last {
            items.insert(RepeatingScheduleValue(startTime: 0, value: last.value), at: 0)
        }
        return DailyQuantitySchedule(unit: .hour(), dailyItems: items)!
    }

    init(hourSchedule: DailyQuantitySchedule<Double>) {
        self.init(items: hourSchedule.items.map {
            Item(startTime: $0.startTime, absorptionTime: HKQuantity(unit: hourSchedule.unit, doubleValue: $0.value).doubleValue(for: .second()))
        })
    }
}
