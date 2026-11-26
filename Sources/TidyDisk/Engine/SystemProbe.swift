import Foundation
import Darwin
import IOKit
import IOKit.ps

/// Raw system readers behind the Monitor tab: Mach host statistics, sysctl,
/// IOKit and libproc. No subprocesses, no UI. Every reader is a cheap one-shot
/// call; `SystemSampler` turns the counters into rates.
enum SystemProbe {
    struct Battery: Equatable {
        let percent: Int
        let isCharging: Bool
        let onBattery: Bool
        let cycles: Int?
    }

    enum Pressure { case normal, warning, critical }

    /// One row of the process table: an app with all its helpers, or every
    /// instance of one command-line binary.
    struct ProcessGroup: Identifiable, Equatable {
        /// The `.app` bundle path, or `cli:<name>` for a non-app process.
        let id: String
        let name: String
        /// Outermost enclosing `.app`; nil for a command-line process.
        let appPath: String?
        let count: Int
        /// Percent of one core, so 237 means 2.37 cores busy.
        let cpu: Double
        /// Physical footprint in bytes, summed over the group.
        let memory: Int64
    }

    // MARK: CPU

    private static let host = mach_host_self()

    /// Cumulative scheduler ticks since boot, all cores together.
    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    /// 1, 5 and 15 minute load averages.
    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : [0, 0, 0]
    }

    // MARK: Memory

    /// Used memory in bytes: (active + wired + compressor) × page size.
    static func memoryUsed() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return Int64(pages * UInt64(pageSize))
    }

    /// Swap in use, bytes.
    static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    /// The kernel's memory pressure level (1 normal, 2 warning, 4 critical).
    static func pressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    // MARK: GPU

    /// Busiest GPU, 0…1. Nil when no accelerator publishes "Device Utilization %".
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = registryValue(service, "PerformanceStatistics") as? [String: Any],
                  let percent = stats["Device Utilization %"] as? NSNumber else { continue }
            best = max(best ?? 0, min(max(percent.doubleValue / 100, 0), 1))
        }
        return best
    }

    // MARK: Network

    /// Bytes received and sent since boot over the real interfaces. Loopback is
    /// skipped, and so are tunnels and bridges, whose traffic already shows up
    /// on the interface that carries it.
    static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 8)
        defer { buffer.deallocate() }
        guard sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 else { return nil }

        let virtual: Set<Int32> = [IFT_LOOP, IFT_OTHER, IFT_GIF, IFT_STF, IFT_BRIDGE]
        var received: UInt64 = 0, sent: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= length {
                let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if !virtual.contains(Int32(info.ifm_data.ifi_type)) {
                    received += info.ifm_data.ifi_ibytes
                    sent += info.ifm_data.ifi_obytes
                }
            }
            offset += messageLength
        }
        return (received, sent)
    }

    // MARK: Battery

    /// The internal battery, or nil on a Mac without one.
    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let capacity = info[kIOPSMaxCapacityKey] as? Int, capacity > 0 else { continue }
            return Battery(
                percent: min(max(Int((Double(current) / Double(capacity) * 100).rounded()), 0), 100),
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                onBattery: info[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                cycles: batteryCycles())
        }
        return nil
    }

    private static func batteryCycles() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return (registryValue(service, "CycleCount") as? NSNumber)?.intValue
    }

    // MARK: Uptime and model

    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }

    /// "MacBook Air" from the device tree's product name ("MacBook Air (13-inch,
    /// M4, 2025)"); "Mac" when the firmware does not publish one (Intel).
    static func modelName() -> String {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return "Mac" }
        defer { IOObjectRelease(entry) }
        guard let data = registryValue(entry, "product-name") as? Data,
              let full = String(data: data.prefix { $0 != 0 }, encoding: .utf8) else { return "Mac" }
        let short = full.components(separatedBy: " (")[0].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? "Mac" : short
    }

    private static func registryValue(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    // MARK: Processes

    /// Cumulative CPU time and footprint of one process. Fails for processes
    /// owned by other users; callers skip those.
    static func usage(of pid: pid_t) -> (cpuNanos: UInt64, footprint: UInt64, started: UInt64)? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        // CPU times come back in Mach ticks, which are not nanoseconds on Apple silicon.
        let ticks = info.ri_user_time + info.ri_system_time
        return (ticks * UInt64(timebase.numer) / UInt64(timebase.denom),
                info.ri_phys_footprint, info.ri_proc_start_abstime)
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    static func allPids() -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        return count > 0 ? pids.prefix(min(count, capacity)).filter { $0 > 0 } : []
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Which table row an executable belongs to: the outermost `.app` on its
    /// path (so every Chrome helper counts as Google Chrome), else its own name.
    static func group(forExecutable path: String) -> (id: String, name: String, appPath: String?) {
        let parts = path.split(separator: "/")
        if let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            let bundle = "/" + parts[...index].joined(separator: "/")
            return (bundle, String(parts[index].dropLast(4)), bundle)
        }
        // Chromium browsers run their main process from a signed copy named
        // "<App>.app.bundle" in a temp folder; the sampler folds it into the app.
        if let clone = parts.first(where: { $0.hasSuffix(cloneSuffix) }) {
            let name = String(clone.dropLast(cloneSuffix.count))
            return (clonePrefix + name, name, nil)
        }
        let name = parts.last.map(String.init) ?? path
        return ("cli:" + name, name, nil)
    }

    private static let cloneSuffix = ".app.bundle"
    static let clonePrefix = "clone:"
}

// MARK: - Sampler

/// Turns the cumulative counters into rates. It remembers the previous
/// reading, so use one instance from one serial queue.
final class SystemSampler: @unchecked Sendable {
    struct Snapshot {
        /// 0…1; nil on the first reading (a rate needs two).
        var cpu: Double?
        var load: [Double]
        var memUsed: Int64?
        var swapUsed: Int64
        var pressure: SystemProbe.Pressure
        var gpu: Double?
        /// Bytes per second; nil on the first reading.
        var netDown: Double?
        var netUp: Double?
        var battery: SystemProbe.Battery?
        /// Nil when processes were not sampled or have no rate yet.
        var processes: [SystemProbe.ProcessGroup]?
    }

    /// Per-process sampling walks every pid, so it is off unless asked for.
    var includeProcesses = false {
        didSet { if !includeProcesses { processTimes = [:]; processGroups = [:]; processClock = nil } }
    }

    /// How many rows to keep per sort order.
    private static let keep = 12
    /// A gap this long means sampling was off; rates across it would mislead.
    private static let staleAfter: TimeInterval = 10

    private var clock: TimeInterval?
    private var cpuTicks: (busy: UInt64, total: UInt64)?
    private var netBytes: (received: UInt64, sent: UInt64)?

    private struct ProcessKey: Hashable { let pid: pid_t; let started: UInt64 }
    private var processClock: TimeInterval?
    private var processTimes: [ProcessKey: UInt64] = [:]
    private var processGroups: [ProcessKey: (id: String, name: String, appPath: String?)] = [:]

    /// Forget the previous reading (after a pause).
    func reset() {
        clock = nil
        cpuTicks = nil
        netBytes = nil
        processClock = nil
        processTimes = [:]
    }

    func sample() -> Snapshot {
        let now = ProcessInfo.processInfo.systemUptime
        if let clock, now - clock > Self.staleAfter { reset() }
        let elapsed = clock.map { now - $0 }

        var snapshot = Snapshot(load: SystemProbe.loadAverage(), memUsed: SystemProbe.memoryUsed(),
                                swapUsed: SystemProbe.swapUsed(), pressure: SystemProbe.pressure(),
                                gpu: SystemProbe.gpuUtilization(), battery: SystemProbe.battery())

        let ticks = SystemProbe.cpuTicks()
        if let ticks, let last = cpuTicks, ticks.total > last.total, ticks.busy >= last.busy {
            snapshot.cpu = min(Double(ticks.busy - last.busy) / Double(ticks.total - last.total), 1)
        }
        cpuTicks = ticks

        let bytes = SystemProbe.networkBytes()
        if let bytes, let last = netBytes, let elapsed, elapsed > 0.2 {
            // A counter that went backwards means an interface left; call it zero.
            snapshot.netDown = bytes.received >= last.received
                ? Double(bytes.received - last.received) / elapsed : 0
            snapshot.netUp = bytes.sent >= last.sent ? Double(bytes.sent - last.sent) / elapsed : 0
        }
        netBytes = bytes
        clock = now

        if includeProcesses { snapshot.processes = sampleProcesses(now: now) }
        return snapshot
    }

    /// Take the first per-process reading now, so the next sample already has rates.
    func primeProcesses() {
        _ = sampleProcesses(now: ProcessInfo.processInfo.systemUptime)
    }

    private func sampleProcesses(now: TimeInterval) -> [SystemProbe.ProcessGroup]? {
        struct Total { var name: String; var appPath: String?; var count = 0; var cpu = 0.0; var memory: Int64 = 0 }

        let elapsed = processClock.map { now - $0 }
        var times: [ProcessKey: UInt64] = [:]
        var groups: [ProcessKey: (id: String, name: String, appPath: String?)] = [:]
        var totals: [String: Total] = [:]

        for pid in SystemProbe.allPids() {
            guard let usage = SystemProbe.usage(of: pid) else { continue }
            let key = ProcessKey(pid: pid, started: usage.started)
            guard let group = processGroups[key]
                    ?? SystemProbe.executablePath(of: pid).map(SystemProbe.group(forExecutable:)) else {
                continue
            }
            times[key] = usage.cpuNanos
            groups[key] = group

            var total = totals[group.id] ?? Total(name: group.name, appPath: group.appPath)
            total.count += 1
            total.memory += Int64(clamping: usage.footprint)
            if let elapsed, elapsed > 0.2, let last = processTimes[key], usage.cpuNanos >= last {
                total.cpu += Double(usage.cpuNanos - last) / (elapsed * 1_000_000_000) * 100
            }
            totals[group.id] = total
        }
        processTimes = times
        processGroups = groups
        processClock = now
        for (id, clone) in totals where id.hasPrefix(SystemProbe.clonePrefix) {
            guard let app = totals.first(where: { $0.value.appPath != nil && $0.value.name == clone.name })?.key
            else { continue }
            totals[app]?.count += clone.count
            totals[app]?.cpu += clone.cpu
            totals[app]?.memory += clone.memory
            totals[id] = nil
        }
        // The first pass has no CPU rates yet; wait for the second.
        guard elapsed != nil else { return nil }

        let all = totals.map {
            SystemProbe.ProcessGroup(id: $0.key, name: $0.value.name, appPath: $0.value.appPath,
                                     count: $0.value.count, cpu: $0.value.cpu, memory: $0.value.memory)
        }
        let byCPU = all.sorted { $0.cpu > $1.cpu }.prefix(Self.keep)
        let byMemory = all.sorted { $0.memory > $1.memory }.prefix(Self.keep)
        var seen = Set<String>()
        return (byCPU + byMemory).filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Speed test

/// One timed download from Cloudflare. Only ever started by the user.
enum SpeedTest {
    static let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    /// Slow links stop here and report what they managed.
    static let maxSeconds: TimeInterval = 8

    /// Download speed in megabits per second, or nil when the test failed.
    static func run() async -> Double? {
        await withCheckedContinuation { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            let timing = Timing { continuation.resume(returning: $0) }
            let session = URLSession(configuration: configuration, delegate: timing, delegateQueue: nil)
            session.dataTask(with: url).resume()
        }
    }

    /// Times the body only (first chunk to last), so the TLS handshake does
    /// not drag the figure down. URLSession calls it on one serial queue.
    private final class Timing: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let done: (Double?) -> Void
        private var firstChunk: TimeInterval?
        private var lastChunk: TimeInterval = 0
        private var bytes = 0
        private var finished = false

        init(done: @escaping (Double?) -> Void) { self.done = done }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            completionHandler((response as? HTTPURLResponse)?.statusCode == 200 ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let now = ProcessInfo.processInfo.systemUptime
            guard let firstChunk else {
                self.firstChunk = now
                lastChunk = now
                return
            }
            bytes += data.count
            lastChunk = now
            if now - firstChunk >= SpeedTest.maxSeconds { finish(session) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            finish(session)
        }

        private func finish(_ session: URLSession) {
            guard !finished else { return }
            finished = true
            session.invalidateAndCancel()
            let seconds = lastChunk - (firstChunk ?? lastChunk)
            done(bytes > 250_000 && seconds > 0.05 ? Double(bytes) * 8 / seconds / 1_000_000 : nil)
        }
    }
}
