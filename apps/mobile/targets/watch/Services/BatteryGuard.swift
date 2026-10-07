import Foundation
import ThresholdEngine
import WatchKit

@MainActor
final class BatteryGuard {
    var levelLimit: () -> Double = { 0.10 }
    var onReading: (Double?, TimeInterval?) -> Void = { _, _ in }
    var onDepleted: () -> Void = {}

    private var readings: [BatteryEstimate.Reading] = []
    private var task: Task<Void, Never>?
    private var triggered = false

    func start() {
        stop()
        triggered = false
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
    }

    private func sample() {
        guard !Task.isCancelled else { return }
        let device = WKInterfaceDevice.current()
        let raw = device.batteryLevel
        guard device.batteryState != .unknown, raw >= 0 else {
            onReading(nil, nil)
            return
        }
        let level = Double(raw)
        guard device.batteryState == .unplugged else {
            readings.removeAll()
            onReading(level, nil)
            return
        }
        let now = Date()
        readings.append(BatteryEstimate.Reading(date: now, level: level))
        let cutoff = now.addingTimeInterval(-BatteryEstimate.window)
        readings.removeAll { $0.date < cutoff }
        let remaining = BatteryEstimate.secondsRemaining(
            readings: readings,
            now: now,
            until: levelLimit()
        )
        onReading(level, remaining)
        guard !triggered, isAtOrBelowGuard(level) else { return }
        triggered = true
        onDepleted()
    }

    private func isAtOrBelowGuard(_ level: Double) -> Bool {
        let percent = Int((level * 100).rounded())
        let limit = Int((levelLimit() * 100).rounded())
        return percent <= limit
    }
}
