//
//  DeferredMealBolusSelectionView.swift
//  Loop
//
//  Created by Claude Code for Deferred Meal Bolus experiment
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//
import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct DeferredMealBolusSelectionView: View {
    @Binding var isDeferredMealBolusEnabled: Bool
    var automaticDosingStrategy: AutomaticDosingStrategy

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Deferred Meal Bolus", comment: "Title for deferred meal bolus experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("Deferred Meal Bolus tracks the full intended bolus amount when entering a meal that is blocked due to low glucose predictions.\n\nWhen glucose predictions recover and become safe (all predictions above target), Loop will deliver the full remaining meal bolus amount in addition to any automatic dosing, respecting maximum bolus and IOB limits.\n\nThis ensures you receive the full meal bolus you intended, rather than only partial automatic doses after predictions recover.\n\nDeferred boluses expire after 4 hours and are removed if the associated carb entry is deleted or edited.", comment: "Description of Deferred Meal Bolus toggle."))
                    .foregroundColor(.secondary)

                if automaticDosingStrategy != .automaticBolus {
                    Divider()
                    Text(NSLocalizedString("⚠️ This experiment only works with Automatic Bolus dosing strategy.", comment: "Warning that deferred meal bolus requires automatic bolus"))
                        .foregroundColor(.orange)
                        .font(.callout)
                }

                Divider()

                Toggle(NSLocalizedString("Enable Deferred Meal Bolus", comment: "Title for Deferred Meal Bolus toggle"), isOn: $isDeferredMealBolusEnabled)
                    .padding(.top, 20)
                    .disabled(automaticDosingStrategy != .automaticBolus)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

}

struct DeferredMealBolusSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeferredMealBolusSelectionView(isDeferredMealBolusEnabled: .constant(true), automaticDosingStrategy: .automaticBolus)
    }
}
