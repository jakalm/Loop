//
//  CarbAbsorptionScheduleView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct CarbAbsorptionScheduleView: View {
    @Environment(\.dismissAction) private var dismiss

    @State private var schedule: CarbAbsorptionTimeSchedule

    private let absorptionStep = TimeInterval.minutes(30)

    private let absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    init(schedule: CarbAbsorptionTimeSchedule = UserDefaults.standard.carbAbsorptionTimeSchedule) {
        _schedule = State(initialValue: schedule)
    }

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("New carb entries get the absorption time for the time of day of the meal. Changing the meal time updates it, unless you have picked a favorite food or changed the absorption time yourself. 🍭 and 🍕 keep their fixed times.")) {
                    Toggle("Default by Time of Day", isOn: $schedule.isEnabled)
                }

                if schedule.isEnabled {
                    Section(header: Text("Meals Starting From")) {
                        ForEach($schedule.items) { $item in
                            itemRow($item)
                        }
                        .onDelete { offsets in
                            schedule.items.remove(atOffsets: offsets)
                        }

                        Button(action: addItem) {
                            Label("Add Period", systemImage: "plus")
                        }
                    }
                }
            }
            .insetGroupedListStyle()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: dismiss) {
                        Text("Done")
                    }
                }
            }
            .navigationBarTitle(String(localized: "Carb Absorption Times", comment: "Title for carb absorption time schedule view"), displayMode: .large)
        }
        .onChange(of: schedule) { newValue in
            if newValue.items != newValue.sortedItems {
                schedule.items = newValue.sortedItems
            } else {
                UserDefaults.standard.carbAbsorptionTimeSchedule = newValue
            }
        }
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
        let start = schedule.sortedItems.last.map { ($0.startTime + .hours(1)).truncatingRemainder(dividingBy: .hours(24)) } ?? 0
        schedule.items.append(CarbAbsorptionTimeSchedule.Item(startTime: start, absorptionTime: .hours(3)))
    }
}

struct CarbAbsorptionScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        CarbAbsorptionScheduleView(schedule: CarbAbsorptionTimeSchedule(isEnabled: true, items: CarbAbsorptionTimeSchedule.suggested.items))
    }
}
