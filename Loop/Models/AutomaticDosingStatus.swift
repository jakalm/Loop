//
//  AutomaticDosingStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2021-05-28.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore

class AutomaticDosingStatus {
    @Published var loopMode: LoopMode
    @Published var isAutomaticDosingAllowed: Bool

    /// Current glucose value in mg/dL, used for calibration mode decisions
    var currentGlucoseValue: Double?

    /// Computed property that determines if automatic dosing should be enabled
    /// based on the current loop mode and glucose level (for calibration mode)
    var automaticDosingEnabled: Bool {
        return loopMode.shouldEnableAutomaticDosing(glucoseValue: currentGlucoseValue)
    }

    init(loopMode: LoopMode,
         isAutomaticDosingAllowed: Bool)
    {
        self.loopMode = loopMode
        self.isAutomaticDosingAllowed = isAutomaticDosingAllowed
        self.currentGlucoseValue = nil
    }

    /// Legacy init for backward compatibility
    init(automaticDosingEnabled: Bool,
         isAutomaticDosingAllowed: Bool)
    {
        self.loopMode = automaticDosingEnabled ? .closed : .open
        self.isAutomaticDosingAllowed = isAutomaticDosingAllowed
        self.currentGlucoseValue = nil
    }
}
