import WatchKit

final class HapticAlertService {
    private var burst: Task<Void, Never>?

    func warning() {
        play([.directionUp, .notification, .notification])
    }

    func thresholdReached() {
        play([.failure, .retry])
    }

    func attention() {
        play([.start])
    }

    func batteryGuard() {
        play([.directionDown, .notification, .stop])
    }

    private func play(_ types: [WKHapticType]) {
        burst?.cancel()
        guard let first = types.first else { return }
        WKInterfaceDevice.current().play(first)
        let rest = Array(types.dropFirst())
        guard !rest.isEmpty else { return }
        burst = Task { @MainActor in
            for type in rest {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(type)
            }
        }
    }
}
