import Foundation

@MainActor
final class HeartRateMonitor: ObservableObject {
    @Published private(set) var currentBPM: Double?
    @Published private(set) var status = "Not started"
}
