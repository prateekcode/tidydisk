import Foundation

/// Live system readings for the Monitor tab and the Overview summary.
/// Sampling only runs between `start()` and `stop()` (ref-counted), so the
/// app costs nothing while no screen is showing it: no timer exists at all
/// when the count is zero or the user paused.
@MainActor
final class MonitorStore: ObservableObject {
    typealias Battery = SystemProbe.Battery
    typealias Pressure = SystemProbe.Pressure
    typealias ProcessGroup = SystemProbe.ProcessGroup

    enum Health { case good, fair, poor }

    enum SpeedTestState: Equatable {
        case idle, running, failed
        /// Megabits per second.
        case done(mbps: Double)
    }

    /// Seconds between samples.
    static let interval: TimeInterval = 3
    /// Samples kept per history: three minutes.
    static let historyLength = 60

    // MARK: Readings

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

    /// Swap in use, bytes.
    @Published private(set) var swapUsed: Int64 = 0
    /// Free share of the startup disk, 0…1. Feeds `health`.
    @Published private(set) var diskFree: Double = MonitorStore.readDiskFree()
    /// Top apps and processes (the leaders by CPU and by memory, unsorted).
    /// Empty until the Monitor tab asks for them with `startProcesses()`.
    @Published private(set) var processes: [ProcessGroup] = []
    @Published private(set) var paused = false
    @Published private(set) var speedTest: SpeedTestState = .idle

    // Histories, oldest → newest, at most `historyLength` samples.
    /// 0…1.
    @Published private(set) var cpuHistory: [Double] = []
    /// 0…1.
    @Published private(set) var gpuHistory: [Double] = []
    /// Used share of physical memory, 0…1.
    @Published private(set) var memHistory: [Double] = []
    /// Bytes per second.
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var netUpHistory: [Double] = []

    /// "MacBook Air"; "Mac" when the firmware does not say.
    let modelName = SystemProbe.modelName()
    let bootTime = SystemProbe.bootTime()

    /// Seconds since boot.
    var uptime: TimeInterval { bootTime.map { max(Date().timeIntervalSince($0), 0) } ?? 0 }

    /// Health rule, worst match wins:
    /// - poor: memory pressure is critical, or under 5% of the disk is free;
    /// - fair: memory pressure is warning, or under 10% of the disk is free,
    ///   or CPU has stayed above 85% for the last five samples (15 seconds);
    /// - good: everything else.
    var health: Health {
        if pressure == .critical || diskFree < 0.05 { return .poor }
        let cpuSustained = cpuHistory.count >= 5 && cpuHistory.suffix(5).allSatisfy { $0 > 0.85 }
        if pressure == .warning || diskFree < 0.10 || cpuSustained { return .fair }
        return .good
    }

    // MARK: Lifecycle

    private let sampler = SystemSampler()
    private let queue = DispatchQueue(label: "com.riekapps.tidydisk.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var clients = 0
    private var processClients = 0
    private var lastSample: Date?

    /// A screen that shows live readings calls this from `onAppear`.
    func start() {
        clients += 1
        reschedule()
    }

    /// The matching call from `onDisappear`.
    func stop() {
        clients = max(clients - 1, 0)
        reschedule()
    }

    /// Also sample the per-process table (Monitor tab only: it walks every pid).
    func startProcesses() {
        processClients += 1
        guard processClients == 1 else { return }
        queue.async { [sampler] in
            sampler.includeProcesses = true
            sampler.primeProcesses()
        }
    }

    func stopProcesses() {
        processClients = max(processClients - 1, 0)
        guard processClients == 0 else { return }
        queue.async { [sampler] in sampler.includeProcesses = false }
        processes = []
    }

    /// Freeze the readings: the timer is cancelled, not just ignored.
    func pause() {
        paused = true
        reschedule()
    }

    func resume() {
        paused = false
        reschedule()
    }

    /// One reading right now; works while paused.
    func refresh() {
        queue.async(execute: sampleWork())
    }

    /// The timer exists only while a screen is listening and the user has not paused.
    private func reschedule() {
        let shouldRun = clients > 0 && !paused
        if shouldRun, timer == nil {
            let age = lastSample.map { Date().timeIntervalSince($0) } ?? .infinity
            // After a break the old curve would sit next to new samples as if
            // no time had passed, so start the histories again.
            if age > Self.interval * 3 { clearHistories() }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            if age < Self.interval {
                // Another screen was sampling a moment ago: keep its rhythm.
                timer.schedule(deadline: .now() + (Self.interval - age), repeating: Self.interval,
                               leeway: .milliseconds(200))
            } else {
                // One reading at once, a second after a second (rates need two), then every interval.
                timer.schedule(deadline: .now() + 1, repeating: Self.interval, leeway: .milliseconds(200))
                refresh()
            }
            timer.setEventHandler(handler: sampleWork())
            self.timer = timer
            timer.resume()
        } else if !shouldRun, let timer {
            timer.cancel()
            self.timer = nil
        }
    }

    /// Runs on `queue`: read everything, then hop to the main actor to publish.
    private func sampleWork() -> @Sendable () -> Void {
        { [sampler, weak self] in
            let snapshot = sampler.sample()
            let diskFree = MonitorStore.readDiskFree()
            Task { @MainActor [weak self] in self?.apply(snapshot, diskFree: diskFree) }
        }
    }

    private func apply(_ snapshot: SystemSampler.Snapshot, diskFree: Double) {
        lastSample = Date()
        load = snapshot.load
        pressure = snapshot.pressure
        swapUsed = snapshot.swapUsed
        battery = snapshot.battery
        gpu = snapshot.gpu
        self.diskFree = diskFree
        if let used = snapshot.memUsed {
            memUsed = used
            push(Double(used) / Double(max(memTotal, 1)), to: &memHistory)
        }
        if let value = snapshot.cpu {
            cpu = value
            push(value, to: &cpuHistory)
        }
        if let value = snapshot.gpu { push(value, to: &gpuHistory) }
        if let down = snapshot.netDown, let up = snapshot.netUp {
            netDown = down
            netUp = up
            push(down, to: &netDownHistory)
            push(up, to: &netUpHistory)
        }
        if let list = snapshot.processes, processClients > 0 { processes = list }
    }

    private func push(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func clearHistories() {
        cpuHistory = []
        gpuHistory = []
        memHistory = []
        netDownHistory = []
        netUpHistory = []
    }

    nonisolated private static func readDiskFree() -> Double {
        let total = Engine.totalDiskSpace()
        return total > 0 ? Double(Engine.freeDiskSpace()) / Double(total) : 1
    }

    // MARK: Speed test

    /// One download from Cloudflare, timed. Only the Run button calls this.
    func runSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        Task {
            let mbps = await SpeedTest.run()
            speedTest = mbps.map { .done(mbps: $0) } ?? .failed
        }
    }
}
