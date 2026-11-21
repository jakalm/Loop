//
//  CarbAbsorptionTimeScheduleTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit

@testable import Loop

class CarbAbsorptionTimeScheduleTests: XCTestCase {

    private var calendar: Calendar!
    private let base: CarbStore.DefaultAbsorptionTimes = (fast: .minutes(30), medium: .hours(3), slow: .hours(5))

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: hour, minute: minute))!
    }

    private var schedule: CarbAbsorptionTimeSchedule {
        var s = CarbAbsorptionTimeSchedule.suggested
        s.isEnabled = true
        return s
    }

    func testPicksItemForTimeOfDay() {
        XCTAssertEqual(schedule.absorptionTime(at: date(hour: 7, minute: 20), calendar: calendar), .hours(2.5))
        XCTAssertEqual(schedule.absorptionTime(at: date(hour: 10), calendar: calendar), .hours(4.5))
        XCTAssertEqual(schedule.absorptionTime(at: date(hour: 18, minute: 30), calendar: calendar), .hours(4.5))
        XCTAssertEqual(schedule.absorptionTime(at: date(hour: 22), calendar: calendar), .hours(5))
    }

    func testTimeBeforeFirstStartWrapsToLastItem() {
        XCTAssertEqual(schedule.absorptionTime(at: date(hour: 1), calendar: calendar), .hours(5))
    }

    func testUnsortedItemsAreHandled() {
        var s = schedule
        s.items.reverse()
        XCTAssertEqual(s.absorptionTime(at: date(hour: 12), calendar: calendar), .hours(4.5))
    }

    func testDisabledOrEmptyScheduleFallsBackToBase() {
        var disabled = schedule
        disabled.isEnabled = false
        XCTAssertNil(disabled.absorptionTime(at: date(hour: 12), calendar: calendar))
        XCTAssertEqual(disabled.defaultAbsorptionTimes(base: base, at: date(hour: 12), calendar: calendar).medium, .hours(3))

        var empty = schedule
        empty.items = []
        XCTAssertNil(empty.absorptionTime(at: date(hour: 12), calendar: calendar))
    }

    func testOnlyMediumIsReplaced() {
        let times = schedule.defaultAbsorptionTimes(base: base, at: date(hour: 12), calendar: calendar)
        XCTAssertEqual(times.fast, .minutes(30))
        XCTAssertEqual(times.medium, .hours(4.5))
        XCTAssertEqual(times.slow, .hours(5))
    }

    func testValuesAreClampedToLoopLimits() {
        let s = CarbAbsorptionTimeSchedule(isEnabled: true, items: [
            .init(startTime: 0, absorptionTime: .minutes(5)),
            .init(startTime: .hours(12), absorptionTime: .hours(20)),
        ])
        XCTAssertEqual(s.absorptionTime(at: date(hour: 6), calendar: calendar), LoopConstants.minCarbAbsorptionTime)
        XCTAssertEqual(s.absorptionTime(at: date(hour: 13), calendar: calendar), LoopConstants.maxCarbAbsorptionTime)
    }

    func testMealTimeChangeFollowsScheduleWhileUntouched() {
        XCTAssertEqual(CarbAbsorptionTimeSchedule.absorptionTimeAfterMealTimeChange(
            current: .hours(2.5), previousMedium: .hours(2.5), newMedium: .hours(4.5), wasEdited: false, usesCustomFoodType: false), .hours(4.5))
    }

    func testMealTimeChangeKeepsUserChoices() {
        // Edited by hand
        XCTAssertNil(CarbAbsorptionTimeSchedule.absorptionTimeAfterMealTimeChange(
            current: .hours(2.5), previousMedium: .hours(2.5), newMedium: .hours(4.5), wasEdited: true, usesCustomFoodType: false))
        // Favorite food or custom food type
        XCTAssertNil(CarbAbsorptionTimeSchedule.absorptionTimeAfterMealTimeChange(
            current: .hours(2.5), previousMedium: .hours(2.5), newMedium: .hours(4.5), wasEdited: false, usesCustomFoodType: true))
        // 🍭 or 🍕 selected, so the current value is not the medium default
        XCTAssertNil(CarbAbsorptionTimeSchedule.absorptionTimeAfterMealTimeChange(
            current: .minutes(30), previousMedium: .hours(2.5), newMedium: .hours(4.5), wasEdited: false, usesCustomFoodType: false))
        // Same period, nothing to change
        XCTAssertNil(CarbAbsorptionTimeSchedule.absorptionTimeAfterMealTimeChange(
            current: .hours(4.5), previousMedium: .hours(4.5), newMedium: .hours(4.5), wasEdited: false, usesCustomFoodType: false))
    }

    func testRoundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "CarbAbsorptionTimeScheduleTests")!
        defaults.removePersistentDomain(forName: "CarbAbsorptionTimeScheduleTests")
        XCTAssertEqual(defaults.carbAbsorptionTimeSchedule, .suggested)
        defaults.carbAbsorptionTimeSchedule = schedule
        XCTAssertEqual(defaults.carbAbsorptionTimeSchedule, schedule)
        defaults.removePersistentDomain(forName: "CarbAbsorptionTimeScheduleTests")
    }
}
