//
//  DeferredMealBolus.swift
//  Loop
//
//  Created for full meal bolus delivery feature
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Represents a meal bolus that was deferred due to low predicted glucose
/// and should be delivered when glucose predictions are safe
struct DeferredMealBolus: Codable, Equatable {

    /// Unique identifier for this deferred bolus
    let id: UUID

    /// The original intended bolus amount in units
    let originalAmount: Double

    /// Reference to the associated carb entry UUID
    let carbEntryUUID: UUID?

    /// When this deferred bolus was created
    let createdAt: Date

    /// Amount in units that has already been delivered toward this bolus
    var deliveredAmount: Double

    /// Calculated remaining amount to deliver
    var remainingAmount: Double {
        return max(0, originalAmount - deliveredAmount)
    }

    /// Whether this deferred bolus has been fully delivered
    var isFullyDelivered: Bool {
        return deliveredAmount >= originalAmount
    }

    /// Whether this deferred bolus has expired (default: 4 hours)
    func hasExpired(at date: Date, timeout: TimeInterval = .hours(4)) -> Bool {
        return date.timeIntervalSince(createdAt) > timeout
    }

    init(id: UUID = UUID(),
         originalAmount: Double,
         carbEntryUUID: UUID?,
         createdAt: Date = Date(),
         deliveredAmount: Double = 0) {
        self.id = id
        self.originalAmount = originalAmount
        self.carbEntryUUID = carbEntryUUID
        self.createdAt = createdAt
        self.deliveredAmount = deliveredAmount
    }

    /// Records that insulin was delivered toward this deferred bolus
    mutating func recordDelivery(amount: Double) {
        deliveredAmount = min(originalAmount, deliveredAmount + amount)
    }
}

/// Storage for managing deferred meal boluses
class DeferredMealBolusStore {

    private var deferredBoluses: [DeferredMealBolus] = []
    private let lock = NSLock()

    /// Adds a new deferred bolus
    func add(_ deferredBolus: DeferredMealBolus) {
        lock.withLock {
            // Remove any existing deferred bolus for the same carb entry
            if let carbUUID = deferredBolus.carbEntryUUID {
                deferredBoluses.removeAll { $0.carbEntryUUID == carbUUID }
            }
            deferredBoluses.append(deferredBolus)
        }
    }

    /// Gets all active (not fully delivered, not expired) deferred boluses
    func getActiveDeferredBoluses(at date: Date = Date()) -> [DeferredMealBolus] {
        lock.withLock {
            return deferredBoluses.filter { !$0.isFullyDelivered && !$0.hasExpired(at: date) }
        }
    }

    /// Gets a deferred bolus by ID
    func get(id: UUID) -> DeferredMealBolus? {
        lock.withLock {
            return deferredBoluses.first { $0.id == id }
        }
    }

    /// Records delivery toward a deferred bolus
    func recordDelivery(id: UUID, amount: Double) {
        lock.withLock {
            if let index = deferredBoluses.firstIndex(where: { $0.id == id }) {
                deferredBoluses[index].recordDelivery(amount: amount)
            }
        }
    }

    /// Removes a deferred bolus
    func remove(id: UUID) {
        lock.withLock {
            deferredBoluses.removeAll { $0.id == id }
        }
    }

    /// Removes deferred boluses associated with a carb entry
    func removeForCarbEntry(uuid: UUID) {
        lock.withLock {
            deferredBoluses.removeAll { $0.carbEntryUUID == uuid }
        }
    }

    /// Removes all expired and fully delivered deferred boluses
    func cleanupCompleted(at date: Date = Date()) {
        lock.withLock {
            deferredBoluses.removeAll { $0.isFullyDelivered || $0.hasExpired(at: date) }
        }
    }

    /// Clears all deferred boluses
    func clear() {
        lock.withLock {
            deferredBoluses.removeAll()
        }
    }
}
