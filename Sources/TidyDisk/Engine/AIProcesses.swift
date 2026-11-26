import Foundation
import Darwin

// Live readings for the AI tab: which AI tools are running, the MCP servers
// they started, and what is listening on a local port. Read with libproc and
// one `lsof` per sample; nothing here runs unless `AILiveSampler.sample()` is called.

/// One row of "Running now": every process of a tool, or one kind of MCP server.
struct AIProcessGroup: Identifiable {
    enum Role { case tool, mcp }

    let id: String
    let role: Role
    /// The tool itself, or for an MCP server the tool that started it.
    let toolID: String?
    let title: String
    let detail: String
    /// Processes of a tool, or running copies of an MCP server.
    let count: Int
    /// Percent of one core, summed (two busy cores = 200).
    let cpu: Double
    let memory: Int64
}

/// A TCP port something on this Mac is listening on.
struct AIServer: Identifiable {
    enum Bind: Int {
        /// 127.0.0.1 or ::1: reachable from this Mac only.
        case local
        /// One specific network address.
        case network
        /// Every interface: reachable from the network.
        case all
    }

    let port: Int
    let pid: Int32
    let process: String
    /// The AI tool behind it, or who usually owns the port. Empty when not AI.
    let label: String
    let isAI: Bool
    let bind: Bind

    var id: String { "\(pid):\(port)" }
}

struct AILiveSample {
    /// Tools first, then MCP servers, each by memory.
    var groups: [AIProcessGroup] = []
    /// AI servers first, then by port.
    var servers: [AIServer] = []
    var memory: Int64 = 0
    var cpu: Double = 0
}

/// Takes the samples and remembers the previous one, for CPU deltas.
/// Not thread-safe: the store runs one `sample()` at a time.
final class AILiveSampler: @unchecked Sendable {
    private struct Proc {
        let pid: Int32
        let parent: Int32
        let start: UInt64
        let path: String
        let name: String
        let memory: Int64
        let cpuTime: UInt64
        var cpu: Double = 0
        var tool: Int?
        /// Set when this process is itself an MCP server.
        var mcp: String?
    }

    private var previous: [Int32: (start: UInt64, cpuTime: UInt64)] = [:]
    private var previousClock: UInt64 = 0
    /// Command lines do not change, so each is read once per process.
    private var arguments: [Int32: (start: UInt64, list: [String])] = [:]

    func sample() -> AILiveSample {
        // CPU is a difference between two readings. On the first call take a
        // short second one, so the tab does not open on 0%.
        if previous.isEmpty {
            remember(readProcesses())
            Thread.sleep(forTimeInterval: 0.4)
        }
        var table = readProcesses()
        let clock = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsed = Double(clock &- previousClock)
        for (pid, proc) in table {
            if let before = previous[pid], before.start == proc.start, proc.cpuTime >= before.cpuTime,
               elapsed > 0 {
                table[pid]?.cpu = Double(proc.cpuTime - before.cpuTime) / elapsed * 100
            }
        }
        remember(table, clock: clock)
        classify(&table)

        var sample = AILiveSample()
        let owners = table.mapValues { owner(of: $0, in: table) }
        sample.groups = groups(table: table, owners: owners)
        sample.memory = sample.groups.reduce(0) { $0 + $1.memory }
        sample.cpu = sample.groups.reduce(0) { $0 + $1.cpu }
        sample.servers = servers(table: table, owners: owners)
        return sample
    }

    private func remember(_ table: [Int32: Proc], clock: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) {
        previous = table.mapValues { (start: $0.start, cpuTime: $0.cpuTime) }
        previousClock = clock
        arguments = arguments.filter { table[$0.key]?.start == $0.value.start }
    }

    // MARK: - Process table

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    /// Every process of the current user, with memory and CPU time, matched to a tool by its path.
    private func readProcesses() -> [Int32: Proc] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        let uid = getuid()
        var table: [Int32: Proc] = [:]
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))

        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize, info.pbi_uid == uid,
                  proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            var usage = rusage_info_v2()
            let read = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard read == 0 else { continue }
            let path = String(cString: pathBuffer)
            // rusage times are in Mach ticks, which are not nanoseconds on Apple silicon.
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            table[pid] = Proc(pid: pid, parent: Int32(bitPattern: info.pbi_ppid), start: info.pbi_start_tvsec,
                              path: path, name: (path as NSString).lastPathComponent,
                              memory: Int64(clamping: usage.ri_phys_footprint),
                              cpuTime: ticks * Self.timebase.numer / Self.timebase.denom,
                              tool: AICatalog.toolIndex(forExecutable: path))
        }
        return table
    }

    /// The command line of one of the user's own processes (arguments only, never its environment).
    private func commandLine(of proc: Proc) -> [String] {
        if let cached = arguments[proc.pid], cached.start == proc.start { return cached.list }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, proc.pid]
        var size = 0
        var list: [String] = []
        if sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size {
            var buffer = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 {
                // Layout: argc, the executable path, padding, then argc strings.
                let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
                var index = MemoryLayout<Int32>.size
                while index < size, buffer[index] != 0 { index += 1 }
                while index < size, buffer[index] == 0 { index += 1 }
                while list.count < min(Int(argc), 12), index < size {
                    let start = index
                    while index < size, buffer[index] != 0 { index += 1 }
                    list.append(String(decoding: buffer[start..<index], as: UTF8.self))
                    index += 1
                }
            }
        }
        // Node tools rename themselves ("npm exec some-server --flag"), which leaves
        // the whole command in the first argument.
        if let first = list.first, first.contains(" "), !first.hasPrefix("/") {
            list = first.split(separator: " ").map(String.init) + list.dropFirst()
        }
        arguments[proc.pid] = (proc.start, list)
        return list
    }

    // MARK: - Classification

    /// Programs that run someone else's code, so the command line says what they are.
    private static let launchers = ["node", "npm", "npx", "bun", "bunx", "deno", "tsx", "python", "uv",
                                    "uvx", "pipx", "ruby", "java", "docker"]

    private static func isLauncher(_ name: String) -> Bool {
        let lower = name.lowercased()
        return launchers.contains { lower == $0 || (lower.hasPrefix($0) && $0 == "python") }
    }

    /// Fills in what the path alone cannot tell: interpreters running a tool, and MCP servers.
    /// Only interpreters, tool CLIs and binaries named like an MCP server are read, so a
    /// `grep mcp` that an agent runs for a second never shows up as a server.
    private func classify(_ table: inout [Int32: Proc]) {
        for (pid, proc) in table {
            let launcher = Self.isLauncher(proc.name)
            guard launcher || proc.tool != nil || proc.name.lowercased().contains("mcp") else { continue }
            let line = commandLine(of: proc)

            if proc.tool != nil {
                // A tool's own CLI serving MCP: `codex mcp-server`, `claude mcp serve`.
                if line.dropFirst().prefix(2).contains(where: { $0 == "mcp" || $0 == "mcp-server" }) {
                    table[pid]?.mcp = proc.name + " mcp"
                }
            } else if let server = Self.mcpServer(name: proc.name, arguments: line),
                      server.certain || toolAncestor(of: proc, in: table) != nil {
                table[pid]?.mcp = server.name
            } else if launcher, let tool = AICatalog.toolIndex(forCommand: line) {
                table[pid]?.tool = tool
            }
        }
    }

    /// The nearest ancestor that is an AI tool (and not itself an MCP server).
    private func toolAncestor(of proc: Proc, in table: [Int32: Proc]) -> Proc? {
        var current = table[proc.parent]
        var hops = 0
        while let candidate = current, hops < 32 {
            if candidate.tool != nil, candidate.mcp == nil { return candidate }
            current = table[candidate.parent]
            hops += 1
        }
        return nil
    }

    private static let genericNames: Set<String> = [
        "index.js", "index.mjs", "index.cjs", "main.js", "main.py", "server.js", "server.py", "server.mjs",
        "cli.js", "__main__.py", "start.js", "run.py", "dist", "build", "bin", "src", "lib", ".bin", "mcp",
    ]

    /// Recognises an MCP server from its command line. `certain` is false for a bare
    /// `mcp` subcommand (`firebase-tools mcp`), which only counts under an AI tool.
    static func mcpServer(name: String, arguments: [String]) -> (name: String, certain: Bool)? {
        let words = Array(([name] + arguments.dropFirst()).prefix(10)).filter { !$0.hasPrefix("-") }
        for word in words {
            let lower = word.lowercased()
            let leaf = shortName(word).lowercased()
            let marked = ["mcp-server", "mcp_server", "server-mcp", "@modelcontextprotocol/",
                          "server-filesystem", "/mcp/"].contains { lower.contains($0) }
                || lower.hasPrefix("mcp/")
                || ["mcp-", "mcp_"].contains { leaf.hasPrefix($0) }
                || ["-mcp", "_mcp"].contains { leaf.hasSuffix($0) }
            if marked { return (shortName(word), true) }
        }
        if let index = words.firstIndex(of: "mcp") {
            let host = index > 1 ? shortName(words[index - 1]) + " " : ""
            return (host + "mcp", false)
        }
        return nil
    }

    /// "@scope/ssh-mcp-server@1.2" → "ssh-mcp-server"; "…/mcp/weather/server.py" → "weather".
    static func shortName(_ word: String) -> String {
        var parts = word.split(separator: "/").map(String.init)
        while parts.count > 1, let last = parts.last, genericNames.contains(last) { parts.removeLast() }
        var leaf = parts.last ?? word
        if let at = leaf.lastIndex(of: "@"), at != leaf.startIndex { leaf = String(leaf[..<at]) }
        for ending in [".js", ".mjs", ".cjs", ".ts", ".py"] where leaf.hasSuffix(ending) {
            leaf = String(leaf.dropLast(ending.count))
        }
        return leaf
    }

    private enum Owner {
        case tool(Int)
        /// `root` is the top process of the server; helpers it spawns count with it.
        case mcp(root: Int32)
    }

    /// Which row a process belongs to, if any.
    private func owner(of proc: Proc, in table: [Int32: Proc]) -> Owner? {
        if proc.mcp == nil, let tool = proc.tool { return .tool(tool) }
        // Climb to the top of the MCP server this process is part of.
        var root: Int32?
        var current: Proc? = proc
        var hops = 0
        while let candidate = current, hops < 32 {
            if candidate.mcp != nil {
                root = candidate.pid
            } else if candidate.tool != nil || root != nil {
                break
            }
            current = table[candidate.parent]
            hops += 1
        }
        return root.map { .mcp(root: $0) }
    }

    // MARK: - Rows

    private func groups(table: [Int32: Proc], owners: [Int32: Owner?]) -> [AIProcessGroup] {
        var byTool: [Int: [Proc]] = [:]
        var byServer: [Int32: [Proc]] = [:]
        for (pid, owner) in owners {
            guard let proc = table[pid], let owner else { continue }
            switch owner {
            case .tool(let index): byTool[index, default: []].append(proc)
            case .mcp(let root): byServer[root, default: []].append(proc)
            }
        }

        let tools = byTool.map { index, procs -> AIProcessGroup in
            let tool = AICatalog.tools[index]
            var names: [String] = []
            for proc in procs.sorted(by: { $0.memory > $1.memory }) where !names.contains(proc.name) {
                names.append(proc.name)
            }
            return AIProcessGroup(id: "tool:" + tool.id, role: .tool, toolID: tool.id, title: tool.name,
                                  detail: names.prefix(3).joined(separator: ", ")
                                      + (names.count > 3 ? " and \(names.count - 3) more" : ""),
                                  count: procs.count, cpu: procs.reduce(0) { $0 + $1.cpu },
                                  memory: procs.reduce(0) { $0 + $1.memory })
        }

        // Copies of the same server under the same tool share a row ("ssh-mcp-server ×4").
        struct Server { var copies = 0; var cpu = 0.0; var memory: Int64 = 0; var title = ""; var toolID: String? }
        var servers: [String: Server] = [:]
        for (root, procs) in byServer {
            guard let top = table[root] else { continue }
            let starter = toolAncestor(of: top, in: table).flatMap(\.tool).map { AICatalog.tools[$0] }
            let title = top.mcp ?? top.name
            var server = servers[title + "|" + (starter?.id ?? ""), default: Server()]
            server.copies += 1
            server.cpu += procs.reduce(0) { $0 + $1.cpu }
            server.memory += procs.reduce(0) { $0 + $1.memory }
            server.title = title
            server.toolID = starter?.id
            servers[title + "|" + (starter?.id ?? "")] = server
        }
        let mcp = servers.map { key, server in
            AIProcessGroup(id: "mcp:" + key, role: .mcp, toolID: server.toolID, title: server.title,
                           detail: "MCP server" + (AICatalog.tool(server.toolID).map { " · started by " + $0.name } ?? ""),
                           count: server.copies, cpu: server.cpu, memory: server.memory)
        }
        let order: (AIProcessGroup, AIProcessGroup) -> Bool = {
            $0.memory != $1.memory ? $0.memory > $1.memory : $0.id < $1.id
        }
        return tools.sorted(by: order) + mcp.sorted(by: order)
    }

    // MARK: - Listening ports

    private func servers(table: [Int32: Proc], owners: [Int32: Owner?]) -> [AIServer] {
        // -F prints one field per line: p<pid>, c<command>, then n<address:port> per socket.
        let output = Engine.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]).output
        var pid: Int32 = 0
        var command = ""
        var found: [String: AIServer] = [:]

        for line in output.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard pid > 0, let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let host = String(value[..<colon])
                let bind: AIServer.Bind = host == "*" ? .all
                    : (host == "[::1]" || host == "localhost" || host.hasPrefix("127.")) ? .local : .network

                // A known default port counts even when the process is not recognised.
                var label = AICatalog.owner(ofPort: port).map { $0 + " default port" } ?? ""
                switch owners[pid] ?? nil {
                case .tool(let index)?: label = AICatalog.tools[index].name
                case .mcp?: label = "MCP server"
                case nil: break
                }
                let server = AIServer(port: port, pid: pid, process: table[pid]?.name ?? command, label: label,
                                      isAI: !label.isEmpty, bind: bind)
                // IPv4 and IPv6 sockets of one server are one row; the widest binding wins.
                if let existing = found[server.id], existing.bind.rawValue >= bind.rawValue { continue }
                found[server.id] = server
            default: continue
            }
        }
        return found.values.sorted {
            $0.isAI != $1.isAI ? $0.isAI : ($0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid)
        }
    }
}
