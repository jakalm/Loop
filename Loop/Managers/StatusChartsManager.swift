//
//  StatusChartsManager.swift
//  Loop
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopUI
import LoopKitUI
import SwiftCharts


class StatusChartsManager: ChartsManager {
    enum ChartIndex: Int, CaseIterable {
        case glucose
        case iob
        case dose
        case cob
        case basalRate
    }

    let glucose: PredictedGlucoseChart
    let iob: IOBChart
    let dose: DoseChart
    let cob: COBChart
    let basalRate: BasalRateChart

    init(colors: ChartColorPalette, settings: ChartSettings, traitCollection: UITraitCollection) {
        let glucose = PredictedGlucoseChart(predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
                                            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        let iob = IOBChart()
        let dose = DoseChart()
        let cob = COBChart()
        let basalRate = BasalRateChart()
        self.glucose = glucose
        self.iob = iob
        self.dose = dose
        self.cob = cob
        self.basalRate = basalRate

        super.init(colors: colors, settings: settings, charts: ChartIndex.allCases.map({ (index) -> ChartProviding in
            switch index {
            case .glucose:
                return glucose
            case .iob:
                return iob
            case .dose:
                return dose
            case .cob:
                return cob
            case .basalRate:
                return basalRate
            }
        }), traitCollection: traitCollection)
    }
}

extension StatusChartsManager {
    func setGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucose.setGlucoseValues(glucoseValues)
        invalidateChart(atIndex: ChartIndex.glucose.rawValue)
    }

    func setPredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucose.setPredictedGlucoseValues(glucoseValues)
        invalidateChart(atIndex: ChartIndex.glucose.rawValue)
    }

    func setAlternatePredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucose.setAlternatePredictedGlucoseValues(glucoseValues)
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

    var preMealOverride: TemporaryScheduleOverride? {
        get {
            return glucose.preMealOverride
        }
        set {
            glucose.preMealOverride = newValue
            invalidateChart(atIndex: ChartIndex.glucose.rawValue)
        }
    }

    var scheduleOverride: TemporaryScheduleOverride? {
        get {
            return glucose.scheduleOverride
        }
        set {
            glucose.scheduleOverride = newValue
            invalidateChart(atIndex: ChartIndex.glucose.rawValue)
        }
    }
}

extension StatusChartsManager {
    func setIOBValues(_ iobValues: [InsulinValue]) {
        iob.setIOBValues(iobValues)
        invalidateChart(atIndex: ChartIndex.iob.rawValue)
    }

    func iobChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.iob.rawValue, frame: frame)
    }
}


extension StatusChartsManager {
    func setDoseEntries(_ doseEntries: [DoseEntry]) {
        dose.doseEntries = doseEntries
        invalidateChart(atIndex: ChartIndex.dose.rawValue)
    }

    func doseChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.dose.rawValue, frame: frame)
    }
}


extension StatusChartsManager {
    func setCOBValues(_ cobValues: [CarbValue]) {
        cob.setCOBValues(cobValues)
        invalidateChart(atIndex: ChartIndex.cob.rawValue)
    }

    func cobChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.cob.rawValue, frame: frame)
    }
}

extension StatusChartsManager {
    func setBasalDoses(_ basalDoses: [DoseEntry]) {
        basalRate.setBasalDoses(basalDoses)
        invalidateChart(atIndex: ChartIndex.basalRate.rawValue)
    }

    func basalRateChart(withFrame frame: CGRect) -> Chart? {
        return chart(atIndex: ChartIndex.basalRate.rawValue, frame: frame)
    }
}
