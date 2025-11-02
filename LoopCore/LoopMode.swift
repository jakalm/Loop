//
//  LoopMode.swift
//  Loop
//
//  Created by Claude Code for Loop Mode Selection
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public enum LoopMode: Int, CaseIterable, Codable, Equatable {
    case open = 0
    case closed = 1
    case calibration = 2

    public var localizedTitle: String {
        switch self {
        case .open:
            return NSLocalizedString("Open", comment: "Open Loop mode title")
        case .closed:
            return NSLocalizedString("Closed", comment: "Closed Loop mode title")
        case .calibration:
            return NSLocalizedString("Calibration", comment: "Calibration Loop mode title")
        }
    }

    public var localizedDescription: String {
        switch self {
        case .open:
            return NSLocalizedString("Manual insulin delivery", comment: "Open Loop mode description")
        case .closed:
            return NSLocalizedString("Automatic insulin delivery", comment: "Closed Loop mode description")
        case .calibration:
            return NSLocalizedString("Automatic delivery only when glucose is outside 4.0-11.0 mmol/L range", comment: "Calibration Loop mode description")
        }
    }

    /// Check if automatic dosing should be enabled based on current glucose level
    /// - Parameter glucoseValue: Current glucose value in mg/dL
    /// - Returns: True if automatic dosing should be enabled
    public func shouldEnableAutomaticDosing(glucoseValue: Double?) -> Bool {
        switch self {
        case .open:
            return false
        case .closed:
            return true
        case .calibration:
            guard let glucose = glucoseValue else {
                // No glucose data - default to open loop behavior (safe)
                return false
            }

            // Convert thresholds from mmol/L to mg/dL
            // 4.0 mmol/L = 72 mg/dL
            // 11.0 mmol/L = 198 mg/dL
            let lowerThreshold: Double = 72.0  // 4.0 mmol/L
            let upperThreshold: Double = 198.0 // 11.0 mmol/L

            // Enable automatic dosing if glucose is outside the safe range
            return glucose < lowerThreshold || glucose > upperThreshold
        }
    }
}
