//
//  MealDetailChartsManager.swift
//  Loop
//
//  Created by Claude Code for Settings Recommendations
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopUI
import LoopKitUI
import SwiftCharts

class MealDetailChartsManager: ChartsManager {
    enum ChartIndex: Int, CaseIterable {
        case glucose
        case iob
        case cob
        case dose
        case basalRate
    }

    let glucose: PredictedGlucoseChart
    let iob: IOBChart
    let cob: COBChart
    let dose: DoseChart
    let basalRate: BasalRateChart

    init(colors: ChartColorPalette, settings: ChartSettings, traitCollection: UITraitCollection) {
        let glucose = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        let iob = IOBChart()
        let cob = COBChart()
        let dose = DoseChart()
        let basalRate = BasalRateChart()

        self.glucose = glucose
        self.iob = iob
        self.cob = cob
        self.dose = dose
        self.basalRate = basalRate

        // Create custom time formatter that shows just the hour
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH"  // Shows "01", "02", "13", "14", etc.

        super.init(colors: colors, settings: settings, charts: ChartIndex.allCases.map({ (index) -> ChartProviding in
            switch index {
            case .glucose:
                return glucose
            case .iob:
                return iob
            case .cob:
                return cob
            case .dose:
                return dose
            case .basalRate:
                return basalRate
            }
        }), traitCollection: traitCollection, customTimeFormatter: hourFormatter)
    }
}

extension MealDetailChartsManager {
    func setGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucose.setGlucoseValues(glucoseValues)
        invalidateChart(atIndex: ChartIndex.glucose.rawValue)
    }

    func glucoseChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.glucose.rawValue, frame: frame)
    }

    var targetGlucoseSchedule: GlucoseRangeSchedule? {
        get {
            return glucose.targetGlucoseSchedule
        }
        set {
            glucose.targetGlucoseSchedule = newValue
            invalidateChart(atIndex: ChartIndex.glucose.rawValue)
        }
    }
}

extension MealDetailChartsManager {
    func setIOBValues(_ iobValues: [InsulinValue]) {
        iob.setIOBValues(iobValues)
        invalidateChart(atIndex: ChartIndex.iob.rawValue)
    }

    func iobChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.iob.rawValue, frame: frame)
    }
}

extension MealDetailChartsManager {
    func setDoseEntries(_ doseEntries: [DoseEntry]) {
        dose.doseEntries = doseEntries
        invalidateChart(atIndex: ChartIndex.dose.rawValue)
    }

    func doseChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.dose.rawValue, frame: frame)
    }
}

extension MealDetailChartsManager {
    func setCOBValues(_ cobValues: [CarbValue]) {
        cob.setCOBValues(cobValues)
        invalidateChart(atIndex: ChartIndex.cob.rawValue)
    }

    func cobChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.cob.rawValue, frame: frame)
    }
}

extension MealDetailChartsManager {
    func setBasalDoses(_ basalDoses: [DoseEntry]) {
        basalRate.setBasalDoses(basalDoses)
        invalidateChart(atIndex: ChartIndex.basalRate.rawValue)
    }

    func basalRateChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.basalRate.rawValue, frame: frame)
    }
}
