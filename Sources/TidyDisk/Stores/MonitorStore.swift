import Foundation

/// Live system readings for the Monitor tab and the Overview summary.
/// Sampling only runs between `start()` and `stop()` (ref-counted), so the
/// app costs nothing while no screen is showing it.
@MainActor
final class MonitorStore: ObservableObject {
    struct Battery: Equatable {
        let percent: Int
        let isCharging: Bool
        let onBattery: Bool
        let cycles: Int?
    }

    enum Pressure { case normal, warning, critical }
    enum Health { case good, fair, poor }

    /// 0…1 across all cores.
    @Published var cpu: Double = 0
    @Published var load: [Double] = [0, 0, 0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    @Published var memUsed: Int64 = 0
    let memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published var pressure: Pressure = .normal
    /// Bytes per second.
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var battery: Battery?
    /// 0…1, nil when the driver does not report it.
    @Published var gpu: Double?

    var health: Health { .good }

    func start() {}
    func stop() {}
}
