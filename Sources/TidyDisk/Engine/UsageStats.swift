import Foundation

/// Anonymous usage statistics. **Off unless the user switches them on in Settings.**
///
/// What is sent when it is on: which tab was opened, that a scan or a clean-up
/// finished (with rounded sizes), the app version, the macOS version, the Mac
/// model, the language setting and a random id made on this Mac. Never file
/// names, paths, folder names, account names or anything typed.
///
/// There is no key here on purpose: the app id is public (this is an open
/// repository), the server only accepts writes, and nothing can be read back
/// with it. Switching the setting off erases the id and asks the server to
/// delete what this Mac sent.
enum UsageStats {
    private static let app = "tidydisk"
    private static let server = "https://a.riekapps.com/v1"
    private static let sdk = "macos/0.1.0"

    private enum Keys {
        static let enabled = "usageStatsEnabled"
        static let install = "usageStatsInstall"
        static let installSent = "usageStatsInstallSent"
        static let sequence = "usageStatsSequence"
    }

    private static let queue = DispatchQueue(label: "com.riekapps.tidydisk.usage")
    private static var pending: [[String: Any]] = []
    private static var flushScheduled = false
    private static let session = randomString(10, from: "abcdefghijklmnopqrstuvwxyz0123456789")
    private static var screen: String?

    /// Never from a snapshot, a report or the weekly headless scan.
    private static let isInteractive: Bool = {
        let silent = ["--shot", "--measure", "--scan-notify", "--apps-report"]
        return !CommandLine.arguments.contains(where: silent.contains)
    }()

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set {
            guard newValue != isEnabled else { return }
            if newValue {
                UserDefaults.standard.set(true, forKey: Keys.enabled)
                opened()
            } else {
                forget()
            }
        }
    }

    // MARK: - Events

    /// Call once at launch, and when the setting is switched on.
    static func opened() {
        guard isEnabled else { return }
        if !UserDefaults.standard.bool(forKey: Keys.installSent) {
            UserDefaults.standard.set(true, forKey: Keys.installSent)
            track("$install")
        }
        track("$open", ["cold": true])
    }

    static func screen(_ name: String) {
        guard name != screen else { return }
        var props: [String: Any] = ["name": name]
        if let screen { props["prev"] = screen }
        screen = name
        track("$screen", props)
    }

    static func scanCompleted(seconds: Double, clearable: Int64) {
        track("scan_completed", ["seconds": Int(seconds.rounded()), "clearable_gb": gigabytes(clearable)])
    }

    static func cleanCompleted(freed: Int64) {
        track("clean_completed", ["freed_gb": gigabytes(freed)])
        track("core_action", ["name": "clean"])
    }

    /// Sizes leave this Mac rounded to one decimal of a GB.
    private static func gigabytes(_ bytes: Int64) -> Double {
        (Double(bytes) / 1_000_000_000 * 10).rounded() / 10
    }

    private static func track(_ name: String, _ props: [String: Any] = [:]) {
        guard isEnabled, isInteractive else { return }
        let now = Date()
        let current = screen
        queue.async {
            let sequence = UserDefaults.standard.integer(forKey: Keys.sequence) + 1
            UserDefaults.standard.set(sequence, forKey: Keys.sequence)
            var event: [String: Any] = [
                "id": uuidV7(at: now), "n": name, "t": milliseconds(now), "s": session, "q": sequence,
            ]
            if !props.isEmpty { event["p"] = props }
            if let current, name != "$screen" { event["sc"] = current }
            pending.append(event)
            if pending.count > 500 { pending.removeFirst(pending.count - 500) }
            scheduleFlush()
        }
    }

    // MARK: - Sending

    private static func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 10) {
            flushScheduled = false
            flush()
        }
    }

    private static func flush() {
        guard isEnabled, !pending.isEmpty else { return }
        let events = pending
        pending = []
        let body: [String: Any] = [
            "app": app, "env": environment, "sdk": sdk, "sentAt": milliseconds(Date()),
            "install": installID, "ctx": context, "events": events,
        ]
        post("batch", body) { status in
            // 204 stored, 400 malformed: both are final. Anything else: keep and try later.
            guard status != 204, status != 400 else { return }
            queue.async {
                pending = events + pending
                queue.asyncAfter(deadline: .now() + 300) { flush() }
            }
        }
    }

    /// Switching off: stop, drop what is unsent, ask the server to erase this Mac's events.
    private static func forget() {
        let install = UserDefaults.standard.string(forKey: Keys.install)
        [Keys.enabled, Keys.install, Keys.installSent, Keys.sequence]
            .forEach(UserDefaults.standard.removeObject)
        queue.async { pending = [] }
        if let install { post("forget", ["app": app, "install": install]) { _ in } }
    }

    private static func post(_ route: String, _ body: [String: Any], done: @escaping (Int) -> Void) {
        guard let url = URL(string: "\(server)/\(route)"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return done(400) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, response, _ in
            done((response as? HTTPURLResponse)?.statusCode ?? 0)
        }.resume()
    }

    // MARK: - Identity and context

    private static var installID: String {
        if let saved = UserDefaults.standard.string(forKey: Keys.install) { return saved }
        let made = randomString(32, from: "0123456789abcdef")
        UserDefaults.standard.set(made, forKey: Keys.install)
        return made
    }

    private static var environment: String {
        #if DEBUG
        return "dev"
        #else
        return "prod"
        #endif
    }

    private static var context: [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "platform": "macos",
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "dev",
            "build": info["CFBundleVersion"] as? String ?? "0",
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "device": model,
            "locale": Locale.current.identifier,
            "tz": TimeZone.current.secondsFromGMT() / 60,
        ]
    }

    /// "Mac15,12": the model, not the name the owner gave the Mac.
    private static let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(cString: value)
    }()

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func randomString(_ length: Int, from alphabet: String) -> String {
        let letters = Array(alphabet)
        return String((0..<length).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }

    /// Time-ordered id (RFC 9562 version 7): 48 bits of milliseconds, then random.
    private static func uuidV7(at date: Date) -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let time = UInt64(milliseconds(date))
        for index in 0..<6 { bytes[index] = UInt8((time >> UInt64(8 * (5 - index))) & 0xFF) }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return [(0, 8), (8, 4), (12, 4), (16, 4), (20, 12)].map { start, length in
            let from = hex.index(hex.startIndex, offsetBy: start)
            return String(hex[from..<hex.index(from, offsetBy: length)])
        }.joined(separator: "-")
    }
}
