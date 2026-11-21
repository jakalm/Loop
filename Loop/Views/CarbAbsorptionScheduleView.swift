//
//  CarbAbsorptionScheduleView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

/// Keeps the therapy settings card and the editor in sync with the stored schedule.
final class CarbAbsorptionScheduleStore: ObservableObject {
    static let shared = CarbAbsorptionScheduleStore()

    @Published var schedule: CarbAbsorptionTimeSchedule {
        didSet {
            // Assigning inside didSet does not trigger didSet again.
            if schedule.items != schedule.sortedItems {
                schedule.items = schedule.sortedItems
            }
            if schedule != oldValue {
                UserDefaults.standard.carbAbsorptionTimeSchedule = schedule
            }
        }
    }

    init(schedule: CarbAbsorptionTimeSchedule = UserDefaults.standard.carbAbsorptionTimeSchedule) {
        self.schedule = schedule
    }
}

private let absorptionTimeFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter
}()

private func timeOfDayString(_ secondsSinceMidnight: TimeInterval) -> String {
    let seconds = Int(secondsSinceMidnight)
    let date = Calendar.current.date(bySettingHour: seconds / 3600, minute: (seconds % 3600) / 60, second: 0, of: Date()) ?? Date()
    return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
}

extension TherapySettingsView.AdditionalSetting {
    static var carbAbsorptionSchedule: Self {
        Self(title: String(localized: "Carb Absorption Times", comment: "Title for carb absorption time schedule view"),
             descriptiveText: String(localized: "Default absorption time for new carb entries, by time of day of the meal."),
             summary: { CarbAbsorptionScheduleSummary(store: .shared) },
             destination: { _ in CarbAbsorptionScheduleView(store: .shared) })
    }
}

/// The schedule as shown on the therapy settings card.
struct CarbAbsorptionScheduleSummary: View {
    @ObservedObject var store: CarbAbsorptionScheduleStore

    var body: some View {
        if store.schedule.isEnabled, !store.schedule.items.isEmpty {
            ForEach(store.schedule.sortedItems) { item in
                Divider()
                HStack {
                    Text(timeOfDayString(item.startTime))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(absorptionTimeFormatter.string(from: item.absorptionTime) ?? "")
                }
            }
        } else {
            Divider()
            Text("Off (3 h for 🌮)")
                .foregroundColor(.secondary)
        }
    }
}

struct CarbAbsorptionScheduleView: View {
    @ObservedObject var store: CarbAbsorptionScheduleStore

    private let absorptionStep = TimeInterval.minutes(30)

    var body: some View {
        List {
            Section(footer: Text("New carb entries get the absorption time for the time of day of the meal. Changing the meal time updates it, unless you have picked a favorite food or changed the absorption time yourself. 🍭 and 🍕 keep their fixed times.")) {
                Toggle("Default by Time of Day", isOn: $store.schedule.isEnabled)
            }

            if store.schedule.isEnabled {
                Section(header: Text("Meals Starting From")) {
                    ForEach($store.schedule.items) { $item in
                        itemRow($item)
                    }
                    .onDelete { offsets in
                        store.schedule.items.remove(atOffsets: offsets)
                    }

                    Button(action: addItem) {
                        Label("Add Period", systemImage: "plus")
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .navigationBarTitle(String(localized: "Carb Absorption Times", comment: "Title for carb absorption time schedule view"), displayMode: .large)
    }

    private func itemRow(_ item: Binding<CarbAbsorptionTimeSchedule.Item>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DatePicker("Meal Time", selection: startDate(item), displayedComponents: .hourAndMinute)
            Stepper(value: item.absorptionTime,
                    in: LoopConstants.minCarbAbsorptionTime...LoopConstants.maxCarbAbsorptionTime,
                    step: absorptionStep) {
                HStack {
                    Text("Absorption Time")
                    Spacer()
                    Text(absorptionTimeFormatter.string(from: item.wrappedValue.absorptionTime) ?? "")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Bridges seconds since midnight to a Date today for the time picker.
    private func startDate(_ item: Binding<CarbAbsorptionTimeSchedule.Item>) -> Binding<Date> {
        Binding(
            get: {
                let seconds = Int(item.wrappedValue.startTime)
                return Calendar.current.date(bySettingHour: seconds / 3600, minute: (seconds % 3600) / 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                item.wrappedValue.startTime = TimeInterval((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60)
            }
        )
    }

    private func addItem() {
        let start = store.schedule.sortedItems.last.map { ($0.startTime + .hours(1)).truncatingRemainder(dividingBy: .hours(24)) } ?? 0
        store.schedule.items.append(CarbAbsorptionTimeSchedule.Item(startTime: start, absorptionTime: .hours(3)))
    }
}

struct CarbAbsorptionScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CarbAbsorptionScheduleView(store: CarbAbsorptionScheduleStore(schedule: CarbAbsorptionTimeSchedule(isEnabled: true, items: CarbAbsorptionTimeSchedule.suggested.items)))
        }
    }
}
