//
//  CarbAbsorptionTimeScheduleTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopKitUI

@testable import Loop

class CarbAbsorptionTimeScheduleTests: XCTestCase {

    private var calendar: Calendar!
    private let base: CarbStore.DefaultAbsorptionTimes = (fast: .minutes(30), medium: .hours(3), slow: .hours(5))

    private let schedule = CarbAbsorptionTimeSchedule(items: [
        .init(startTime: .hours(4), absorptionTime: .hours(2.5)),
        .init(startTime: .hours(10), absorptionTime: .hours(4.5)),
        .init(startTime: .hours(15), absorptionTime: .hours(4.5)),
        .init(startTime: .hours(21), absorptionTime: .hours(5)),
    ])

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: hour, minute: minute))!
    }

    func testStandardIsThreeHoursAllDay() {
        for hour in [0, 6, 12, 23] {
            XCTAssertEqual(CarbAbsorptionTimeSchedule.standard.absorptionTime(at: date(hour: hour), calendar: calendar), .hours(3))
        }
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

    func testEmptyScheduleFallsBackToBase() {
        let empty = CarbAbsorptionTimeSchedule(items: [])
        XCTAssertNil(empty.absorptionTime(at: date(hour: 12), calendar: calendar))
        XCTAssertEqual(empty.defaultAbsorptionTimes(base: base, at: date(hour: 12), calendar: calendar).medium, .hours(3))
    }

    func testOnlyMediumIsReplaced() {
        let times = schedule.defaultAbsorptionTimes(base: base, at: date(hour: 12), calendar: calendar)
        XCTAssertEqual(times.fast, .minutes(30))
        XCTAssertEqual(times.medium, .hours(4.5))
        XCTAssertEqual(times.slow, .hours(5))
    }

    func testValuesAreClampedToLoopLimits() {
        let s = CarbAbsorptionTimeSchedule(items: [
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

    func testHourScheduleStartsAtMidnightWithTheWrappedValue() {
        let hourSchedule = schedule.hourSchedule
        XCTAssertEqual(hourSchedule.unit, .hour())
        XCTAssertEqual(hourSchedule.items.map(\.startTime), [0, .hours(4), .hours(10), .hours(15), .hours(21)])
        XCTAssertEqual(hourSchedule.items.map(\.value), [5, 2.5, 4.5, 4.5, 5])
    }

    func testSavingFromHourScheduleKeepsLookups() {
        let saved = CarbAbsorptionTimeSchedule(hourSchedule: schedule.hourSchedule)
        for hour in [1, 7, 12, 18, 23] {
            XCTAssertEqual(saved.absorptionTime(at: date(hour: hour), calendar: calendar),
                           schedule.absorptionTime(at: date(hour: hour), calendar: calendar))
        }
    }

    func testSavingConvertsFromTheScheduleUnit() {
        let minutes = DailyQuantitySchedule(unit: .minute(), dailyItems: [RepeatingScheduleValue(startTime: 0, value: 150.0)])!
        XCTAssertEqual(CarbAbsorptionTimeSchedule(hourSchedule: minutes).items.first?.absorptionTime, .hours(2.5))
    }

    func testRoundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "CarbAbsorptionTimeScheduleTests")!
        defaults.removePersistentDomain(forName: "CarbAbsorptionTimeScheduleTests")
        XCTAssertEqual(defaults.carbAbsorptionTimeSchedule, .standard)
        defaults.carbAbsorptionTimeSchedule = schedule
        XCTAssertEqual(defaults.carbAbsorptionTimeSchedule, schedule)
        defaults.removePersistentDomain(forName: "CarbAbsorptionTimeScheduleTests")
    }

    func testEarlierSavedSchedulesDecode() throws {
        let item = #"{"id":"6F1B1F4E-1C1A-4B8E-9C55-2C7E2D3A0F11","startTime":0,"absorptionTime":9000}"#
        let enabled = try JSONDecoder().decode(CarbAbsorptionTimeSchedule.self, from: Data(#"{"isEnabled":true,"items":[\#(item)]}"#.utf8))
        XCTAssertEqual(enabled.items.map(\.absorptionTime), [.hours(2.5)])
        let disabled = try JSONDecoder().decode(CarbAbsorptionTimeSchedule.self, from: Data(#"{"isEnabled":false,"items":[\#(item)]}"#.utf8))
        XCTAssertEqual(disabled, .standard)
    }

    func testSelectableHoursSurviveThePickersRounding() {
        let hours = TherapySettingsView.AdditionalScheduleSetting.carbAbsorptionSelectableHours
        XCTAssertEqual(hours.map { HKUnit.hour().roundForPicker(value: $0) }, hours)
        XCTAssertEqual(hours.first, 0.5)
        XCTAssertEqual(hours.last, 8)
        XCTAssertTrue(hours.contains(2.5))
    }

    func testHoursAreShownAsHoursAndMinutes() {
        let string = TherapySettingsView.AdditionalScheduleSetting.carbAbsorptionHoursString(2.5)
        XCTAssertTrue(string.contains("2") && string.contains("30"), string)
        XCTAssertFalse(string.contains("2.5") || string.contains("2,5"), string)
    }
}
