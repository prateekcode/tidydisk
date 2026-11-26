import Foundation

// The AI tab's knowledge of the world: which tools exist, where each keeps its
// data, and how to recognise its processes and ports. Everything the tab shows
// is derived from `AICatalog.tools`.
//
// Adding a tool = adding one `AITool` entry. Nothing else needs to change.

/// What an item on disk is, which decides how freely it may be removed.
enum AIKind: String, CaseIterable {
    /// Downloaded weights. Big, re-downloadable, the only kind "older than 90 days" selects.
    case models
    /// Rebuilt or re-downloaded by the tool on its own.
    case cache
    /// Chat history, sessions, settings. Only ever ticked by hand.
    case appData

    /// Badge text and the noun in "14.17 GB models".
    var label: String {
        switch self {
        case .models: return "models"
        case .cache: return "cache"
        case .appData: return "app data"
        }
    }
}

/// One place a tool keeps data. Paths start with `~/`; a last path component
/// may end in `*` to match by prefix (`~/Library/Caches/com.openai.*`).
struct AISource {
    enum Shape {
        /// One item made of every listed path that exists.
        case paths([String])
        /// One item per entry `depth` levels below `dir` (a model per folder or file).
        /// `prefix` / `suffix` filter on the entry name; a prefix is stripped from the
        /// shown name and `--` becomes `/` (Hugging Face's `models--org--name`).
        case each(dir: String, prefix: String, suffix: String, depth: Int)
        /// Whatever in `dir` no other source in the catalog claims, as one item.
        case rest(String)
        /// An Ollama model store: one item per manifest, blobs shared between
        /// models counted once in the tool total.
        case ollama(String)
    }

    let kind: AIKind
    let name: String
    let shape: Shape

    static func paths(_ kind: AIKind, _ name: String, _ paths: [String]) -> AISource {
        AISource(kind: kind, name: name, shape: .paths(paths))
    }

    static func each(_ kind: AIKind, in dir: String, prefix: String = "", suffix: String = "",
                     depth: Int = 1) -> AISource {
        AISource(kind: kind, name: "", shape: .each(dir: dir, prefix: prefix, suffix: suffix, depth: depth))
    }

    static func rest(_ kind: AIKind, _ name: String, of dir: String) -> AISource {
        AISource(kind: kind, name: name, shape: .rest(dir))
    }

    static func ollama(_ dir: String) -> AISource {
        AISource(kind: .models, name: "", shape: .ollama(dir))
    }
}

/// One AI tool: where its data lives and how its processes and ports look.
struct AITool: Identifiable {
    let id: String
    let name: String
    /// SF Symbol shown when the app itself is not installed (CLIs, caches).
    let symbol: String
    /// App bundles (`"Ollama.app"`): the icon, and any process running from inside one.
    var apps: [String] = []
    /// Executable names, matched exactly and case-sensitively (`"ollama"`).
    var binaries: [String] = []
    /// Substrings of an executable path (`"/.lmstudio/"`).
    var pathHints: [String] = []
    /// Lowercase substrings of an interpreter's command line (`node …/gemini-cli/…`).
    var commandHints: [String] = []
    /// Default ports of its local server.
    var ports: [Int] = []
    var sources: [AISource] = []
}

/// One row under a tool: a model, a cache, or its app data.
struct AIItem: Identifiable {
    let id: String
    let toolID: String
    let name: String
    let kind: AIKind
    let bytes: Int64
    /// Regular files inside, capped at `AICatalog.fileCountCap`.
    let files: Int
    /// When a model was downloaded; nil for caches and app data.
    let date: Date?
    /// What "Move to Trash" trashes. For an Ollama model this is its manifest;
    /// the blobs to go with it are worked out at trash time.
    let paths: [String]
    /// Ollama models only: the model store, and each blob the manifest references.
    var ollamaDir: String?
    var blobs: [String: Int64] = [:]

    /// The path shown in the row.
    var location: String { paths.count == 1 ? paths[0] : (paths.first ?? "") }
}

/// A tool that has data on this Mac.
struct AIToolUsage: Identifiable {
    let tool: AITool
    /// Largest first.
    let items: [AIItem]
    /// Bytes that two or more Ollama models share, so the total counts them once.
    let sharedBytes: Int64

    var id: String { tool.id }
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } - sharedBytes }

    func bytes(of kind: AIKind) -> Int64 {
        items.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes } - (kind == .models ? sharedBytes : 0)
    }
}

struct AIDiskScan {
    /// Largest first.
    var tools: [AIToolUsage] = []
    /// Installed tools whose data sits in a folder macOS guards (another app's
    /// sandbox, Documents) and was skipped because Full Disk Access is off.
    var needsAccess: [String] = []
}

enum AICatalog {
    // MARK: - The catalog

    static let tools: [AITool] = [
        AITool(id: "ollama", name: "Ollama", symbol: "shippingbox",
               apps: ["Ollama.app"], binaries: ["ollama"], ports: [11434],
               sources: [
                   .ollama("~/.ollama/models"),
                   .rest(.appData, "Prompt history, keys and logs", of: "~/.ollama"),
               ] + electronApp("~/Library/Application Support/Ollama",
                               caches: ["~/Library/Caches/com.electron.ollama*", "~/Library/Caches/ollama"],
                               data: "Chats and settings")),

        AITool(id: "lmstudio", name: "LM Studio", symbol: "square.stack.3d.up",
               apps: ["LM Studio.app"], binaries: ["lms"], pathHints: ["/.lmstudio/"], ports: [1234],
               sources: [
                   .each(.models, in: "~/.lmstudio/models", depth: 2),
                   .each(.models, in: "~/.cache/lm-studio/models", depth: 2),
                   .paths(.cache, "Inference runtimes", ["~/.lmstudio/extensions/backends",
                                                         "~/.cache/lm-studio/extensions/backends"]),
                   .rest(.appData, "Chats and settings", of: "~/.lmstudio"),
                   .rest(.appData, "Chats and settings (old location)", of: "~/.cache/lm-studio"),
               ] + electronApp("~/Library/Application Support/LM Studio",
                               caches: ["~/Library/Caches/ai.elementlabs.lmstudio*"], data: "App data")),

        AITool(id: "huggingface", name: "Hugging Face", symbol: "face.smiling",
               binaries: ["hf", "huggingface-cli"], commandHints: ["huggingface-cli", "huggingface_hub"],
               sources: [
                   .each(.models, in: "~/.cache/huggingface/hub", prefix: "models--"),
                   .each(.models, in: "~/.cache/huggingface/hub", prefix: "datasets--"),
                   .each(.models, in: "~/.cache/huggingface/hub", prefix: "spaces--"),
                   .paths(.cache, "Download cache", ["~/.cache/huggingface/xet", "~/.cache/huggingface/assets",
                                                     "~/.cache/huggingface/datasets"]),
               ]),

        // Claude Code sits before Claude: its binary lives inside Claude's folders.
        AITool(id: "claude-code", name: "Claude Code", symbol: "terminal",
               binaries: ["claude"], pathHints: ["/claude-code/", "/claude-code@"],
               commandHints: ["@anthropic-ai/claude-code"],
               sources: [
                   .paths(.cache, "Cache", ["~/.claude/cache", "~/Library/Caches/claude-cli-nodejs"]),
                   .paths(.appData, "Session transcripts and memory", ["~/.claude/projects"]),
                   .paths(.appData, "Plugins", ["~/.claude/plugins"]),
                   .rest(.appData, "Settings, skills and history", of: "~/.claude"),
               ]),

        AITool(id: "claude", name: "Claude", symbol: "sparkle",
               apps: ["Claude.app"],
               sources: [
                   // The bundle holds the system image and the session disk, so it is not a cache.
                   .paths(.appData, "Workspace VM and its session disk",
                          ["~/Library/Application Support/Claude/vm_bundles"]),
                   .paths(.cache, "Bundled Claude Code runtimes",
                          ["~/Library/Application Support/Claude/claude-code",
                           "~/Library/Application Support/Claude/claude-code-vm"]),
               ] + electronApp("~/Library/Application Support/Claude",
                               caches: ["~/Library/Caches/com.anthropic.claudefordesktop*"],
                               data: "Chats, sessions and settings")),

        AITool(id: "openai", name: "ChatGPT and Codex", symbol: "bubble.left.and.text.bubble.right",
               apps: ["ChatGPT.app", "Codex.app", "ChatGPT Atlas.app"], binaries: ["codex"],
               pathHints: ["/.codex/", "/Application Support/Codex/", "/codex-runtimes/"],
               commandHints: ["@openai/codex"],
               sources: [
                   .paths(.cache, "Codex runtimes", ["~/.cache/codex-runtimes"]),
                   .paths(.cache, "App cache",
                          ["~/.codex/cache", "~/.codex/.tmp", "~/.codex/tmp", "~/Library/Caches/com.openai.*",
                           "~/Library/Caches/Codex", "~/Library/Caches/ChatGPTHelper"]
                              + electronCaches("~/Library/Application Support/Codex")
                              + electronCaches("~/Library/Application Support/com.openai.chat")),
                   .paths(.appData, "Codex sessions", ["~/.codex/sessions"]),
                   .paths(.appData, "Codex generated images", ["~/.codex/generated_images"]),
                   .rest(.appData, "Codex history, plugins and settings", of: "~/.codex"),
                   .rest(.appData, "Codex app data", of: "~/Library/Application Support/Codex"),
                   .rest(.appData, "ChatGPT conversations and settings",
                         of: "~/Library/Application Support/com.openai.chat"),
                   .rest(.appData, "ChatGPT shared container",
                         of: "~/Library/Group Containers/group.com.openai.chat"),
               ]),

        AITool(id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
               apps: ["Cursor.app"], pathHints: ["/.cursor/"],
               sources: electronApp("~/Library/Application Support/Cursor",
                                    caches: ["~/Library/Caches/Cursor",
                                             "~/Library/Caches/com.todesktop.230313mzl4w4u92*"],
                                    data: "Chats, settings and workspaces")
                   + [.rest(.appData, "Extensions and rules", of: "~/.cursor")]),

        AITool(id: "windsurf", name: "Windsurf", symbol: "wind",
               apps: ["Windsurf.app"], pathHints: ["/.codeium/", "/.windsurf/"],
               sources: electronApp("~/Library/Application Support/Windsurf",
                                    caches: ["~/Library/Caches/com.exafunction.windsurf*"],
                                    data: "Chats, settings and workspaces")
                   + [.rest(.appData, "Cascade history and indexes", of: "~/.codeium"),
                      .rest(.appData, "Extensions", of: "~/.windsurf")]),

        AITool(id: "antigravity", name: "Antigravity", symbol: "arrow.up.forward.circle",
               apps: ["Antigravity.app"], pathHints: ["/.antigravity/", "/.gemini/antigravity/"],
               sources: electronApp("~/Library/Application Support/Antigravity",
                                    caches: ["~/Library/Caches/com.google.antigravity*",
                                             "~/Library/Caches/antigravity-updater"],
                                    data: "Settings and workspaces")
                   + [.paths(.appData, "Conversations, knowledge and recordings", ["~/.gemini/antigravity"]),
                      .rest(.appData, "Extensions", of: "~/.antigravity")]),

        AITool(id: "zed", name: "Zed", symbol: "bolt",
               apps: ["Zed.app", "Zed Preview.app"],
               sources: [
                   .paths(.cache, "Language servers and cache",
                          ["~/Library/Application Support/Zed/languages", "~/Library/Application Support/Zed/node",
                           "~/Library/Caches/Zed", "~/Library/Logs/Zed"]),
                   .rest(.appData, "Threads, extensions and workspace state",
                         of: "~/Library/Application Support/Zed"),
                   .rest(.appData, "Settings", of: "~/.config/zed"),
               ]),

        AITool(id: "copilot", name: "GitHub Copilot", symbol: "chevron.left.forwardslash.chevron.right",
               apps: ["GitHub Copilot for Xcode.app"], binaries: ["copilot", "copilot-language-server"],
               commandHints: ["@github/copilot", "copilot-language-server"],
               sources: [
                   .paths(.cache, "Cache and logs", ["~/Library/Caches/copilot", "~/.copilot/logs",
                                                     "~/Library/Caches/com.github.CopilotForXcode*"]),
                   .rest(.appData, "CLI sessions and settings", of: "~/.copilot"),
                   .rest(.appData, "Sign-in and settings", of: "~/.config/github-copilot"),
                   .paths(.appData, "Chat history in VS Code",
                          ["~/Library/Application Support/Code/User/globalStorage/github.copilot-chat",
                           "~/Library/Application Support/Code/User/globalStorage/github.copilot"]),
                   .rest(.appData, "Copilot for Xcode data",
                         of: "~/Library/Application Support/com.github.CopilotForXcode"),
               ]),

        AITool(id: "gemini", name: "Gemini CLI", symbol: "sparkles",
               binaries: ["gemini"], commandHints: ["@google/gemini-cli", "/gemini-cli/"],
               // ~/.gemini/tmp is not a cache: it holds the per-project chat logs.
               sources: [.rest(.appData, "Sessions, sign-in and settings", of: "~/.gemini")]),

        AITool(id: "comfyui", name: "ComfyUI", symbol: "square.grid.3x3.square",
               apps: ["ComfyUI.app"], commandHints: ["comfyui"], ports: [8188],
               sources: [
                   .each(.models, in: "~/ComfyUI/models", depth: 2),
                   .each(.models, in: "~/Documents/ComfyUI/models", depth: 2),
                   .paths(.appData, "Generated images", ["~/ComfyUI/output", "~/Documents/ComfyUI/output"]),
               ] + electronApp("~/Library/Application Support/ComfyUI", data: "Settings")),

        AITool(id: "drawthings", name: "Draw Things", symbol: "paintbrush.pointed",
               apps: ["Draw Things.app"],
               sources: [
                   .each(.models, in: "~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models"),
                   .rest(.appData, "Projects and generated images",
                         of: "~/Library/Containers/com.liuliu.draw-things/Data/Documents"),
               ]),

        AITool(id: "diffusionbee", name: "DiffusionBee", symbol: "photo.stack",
               apps: ["DiffusionBee.app"],
               sources: [
                   .each(.models, in: "~/.diffusionbee/downloads"),
                   .paths(.appData, "Generated images", ["~/.diffusionbee/images"]),
                   .rest(.appData, "History and settings", of: "~/.diffusionbee"),
               ]),

        AITool(id: "jan", name: "Jan", symbol: "hand.wave",
               apps: ["Jan.app"], ports: [1337],
               sources: [
                   .each(.models, in: "~/jan/models"),
                   .each(.models, in: "~/Library/Application Support/Jan/data/models"),
                   .each(.models, in: "~/Library/Application Support/Jan/data/llamacpp/models"),
                   .rest(.appData, "Threads and settings", of: "~/jan"),
               ] + electronApp("~/Library/Application Support/Jan", data: "Threads and settings")),

        AITool(id: "gpt4all", name: "GPT4All", symbol: "text.bubble",
               apps: ["GPT4All.app"],
               sources: [
                   .each(.models, in: "~/Library/Application Support/nomic.ai/GPT4All", suffix: ".gguf"),
                   .each(.models, in: "~/.cache/gpt4all"),
                   .rest(.appData, "Chats and LocalDocs index", of: "~/Library/Application Support/nomic.ai/GPT4All"),
               ]),

        AITool(id: "speech-mlx", name: "Whisper and MLX", symbol: "waveform",
               apps: ["MacWhisper.app", "superwhisper.app"],
               binaries: ["whisper", "whisper-cli", "whisper-server", "mlx_lm.server"],
               commandHints: ["mlx_lm", "mlx-lm", "mlx_whisper", "whisper"],
               sources: [
                   .each(.models, in: "~/.cache/whisper"),
                   .each(.models, in: "~/.cache/torch/hub/checkpoints"),
                   .each(.models, in: "~/Library/Application Support/MacWhisper/models"),
                   .paths(.cache, "Caches", ["~/Library/Caches/whisper*", "~/Library/Caches/mlx*", "~/.cache/mlx*"]),
               ]),

        AITool(id: "llamacpp", name: "llama.cpp", symbol: "cpu",
               binaries: ["llama-server", "llama-cli"], ports: [8080],
               sources: [.each(.models, in: "~/Library/Caches/llama.cpp", suffix: ".gguf")]),

        AITool(id: "docker-models", name: "Docker Model Runner", symbol: "shippingbox.circle",
               binaries: ["model-runner", "docker-model"], ports: [12434],
               sources: [.paths(.models, "Model store", ["~/.docker/models"])]),
    ]

    /// Default ports of AI servers that are not tied to one tool above.
    static let otherPorts: [Int: String] = [7860: "Gradio"]

    /// Cache folders every Electron or VS Code based app keeps under its support folder.
    private static func electronCaches(_ root: String) -> [String] {
        ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs", "DawnWebGPUCache",
         "DawnGraphiteCache", "GraphiteDawnCache", "component_crx_cache", "Crashpad", "logs"]
            .map { root + "/" + $0 }
    }

    /// An Electron app's support folder: its caches as one item, the rest as app data.
    private static func electronApp(_ root: String, caches: [String] = [], data: String) -> [AISource] {
        [.paths(.cache, "App cache", electronCaches(root) + caches), .rest(.appData, data, of: root)]
    }

    // MARK: - Lookups

    /// Tools hidden below this size: an empty settings folder is not "using the disk".
    static let minimumToolBytes: Int64 = 1_000_000
    /// Entries found by `.each` below this size are placeholders, not models.
    static let minimumModelBytes: Int64 = 1_000_000
    static let fileCountCap = 10_000
    static let staleAfter: TimeInterval = 90 * 86_400

    static func tool(_ id: String?) -> AITool? {
        guard let id else { return nil }
        return tools.first { $0.id == id }
    }

    /// Who usually listens on `port`, when it is a known AI default.
    static func owner(ofPort port: Int) -> String? {
        tools.first { $0.ports.contains(port) }?.name ?? otherPorts[port]
    }

    /// The tool whose executable lives at `path`. Command-line tools and data
    /// folders win over app bundles, so Claude Code inside Claude's folder is Claude Code.
    static func toolIndex(forExecutable path: String) -> Int? {
        let name = (path as NSString).lastPathComponent
        if let index = tools.firstIndex(where: { tool in
            tool.binaries.contains(name) || tool.pathHints.contains { path.contains($0) }
        }) { return index }
        return tools.firstIndex { tool in tool.apps.contains { path.contains("/" + $0 + "/") } }
    }

    /// The tool an interpreter is running (`node …/gemini-cli/…`, `python …/ComfyUI/main.py`).
    static func toolIndex(forCommand arguments: [String]) -> Int? {
        let line = arguments.prefix(6).joined(separator: " ").lowercased()
        return tools.firstIndex { tool in tool.commandHints.contains { line.contains($0) } }
    }

    /// Where the tool's app is installed, for its icon.
    static func appPath(for tool: AITool) -> String? {
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        for app in tool.apps {
            for folder in folders where FileManager.default.fileExists(atPath: folder + "/" + app) {
                return folder + "/" + app
            }
        }
        return nil
    }

    // MARK: - Disk scan

    /// Sizes every catalog tool that has data under `home`. Slow (runs `du`): call off the main thread.
    static func scan(home: String = NSHomeDirectory(), fullDiskAccess: Bool) -> AIDiskScan {
        let context = ScanContext(home: home, fullDiskAccess: fullDiskAccess,
                                  claimed: claimedPaths(home: home, fullDiskAccess: fullDiskAccess))
        var usages = [AIToolUsage?](repeating: nil, count: tools.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: tools.count) { index in
            let usage = usage(of: tools[index], context: context)
            lock.lock()
            usages[index] = usage
            lock.unlock()
        }

        var scan = AIDiskScan()
        scan.tools = usages.compactMap { $0 }
            .filter { $0.bytes >= minimumToolBytes }
            .sorted { $0.bytes > $1.bytes }
        if !fullDiskAccess {
            scan.needsAccess = tools.filter { tool in
                appPath(for: tool) != nil && tool.sources.contains { source in
                    roots(of: source).contains { isProtected(expand($0, home: home), home: home) }
                }
            }.map(\.name)
        }
        return scan
    }

    private struct ScanContext {
        let home: String
        let fullDiskAccess: Bool
        /// Every path a `.paths`, `.each` or `.ollama` source owns, so `.rest` can leave it out.
        let claimed: Set<String>

        func allows(_ path: String) -> Bool {
            fullDiskAccess || !AICatalog.isProtected(path, home: home)
        }
    }

    private static func usage(of tool: AITool, context: ScanContext) -> AIToolUsage? {
        var items: [AIItem] = []
        var shared: Int64 = 0
        for source in tool.sources {
            let found = scanSource(source, tool: tool, context: context)
            items += found.items
            shared += found.shared
        }
        guard !items.isEmpty else { return nil }
        return AIToolUsage(tool: tool, items: items.sorted { $0.bytes > $1.bytes }, sharedBytes: shared)
    }

    private static func scanSource(_ source: AISource, tool: AITool,
                                   context: ScanContext) -> (items: [AIItem], shared: Int64) {
        func item(_ name: String, _ paths: [String], bytes: Int64? = nil, dated: Bool = false) -> AIItem? {
            guard let first = paths.first else { return nil }
            let size = bytes ?? Engine.size(of: paths)
            guard size > 0 else { return nil }
            return AIItem(id: tool.id + ":" + first, toolID: tool.id, name: name, kind: source.kind,
                          bytes: size, files: fileCount(paths),
                          date: dated ? paths.compactMap(created).min() : nil, paths: paths)
        }

        switch source.shape {
        case .paths(let patterns):
            // Checked before the disk is touched: even a stat inside a guarded folder may prompt.
            let paths = patterns.filter { context.allows(expand($0, home: context.home)) }
                .flatMap { resolve($0, home: context.home) }
            return (item(source.name, paths, dated: source.kind == .models).map { [$0] } ?? [], 0)

        case .each(let dir, let prefix, let suffix, let depth):
            let root = expand(dir, home: context.home)
            guard context.allows(root) else { return ([], 0) }
            let items = entries(in: root, depth: depth).compactMap { path -> AIItem? in
                let leaf = (path as NSString).lastPathComponent
                guard leaf.hasPrefix(prefix), leaf.hasSuffix(suffix) else { return nil }
                var name = String(path.dropFirst(root.count + 1))
                if !prefix.isEmpty {
                    name = String(name.dropFirst(prefix.count)).replacingOccurrences(of: "--", with: "/")
                    if prefix != "models--" { name += " (" + prefix.dropLast(3) + ")" }
                }
                let bytes = Engine.size(of: [path])
                guard bytes >= minimumModelBytes else { return nil }
                return item(name, [path], bytes: bytes, dated: true)
            }
            return (items, 0)

        case .rest(let dir):
            let root = expand(dir, home: context.home)
            guard context.allows(root) else { return ([], 0) }
            return (item(source.name, unclaimed(in: root, claimed: context.claimed)).map { [$0] } ?? [], 0)

        case .ollama(let dir):
            return scanOllama(expand(dir, home: context.home), tool: tool)
        }
    }

    // MARK: - Ollama

    struct OllamaModel {
        /// "qwen2.5-coder:14b"
        let name: String
        let manifest: String
        /// Blob path → bytes, for every layer the manifest references and that exists.
        let blobs: [String: Int64]
    }

    /// Every model in an Ollama store: `manifests/<registry>/<namespace>/<name>/<tag>`
    /// is a JSON manifest whose layers point at `blobs/sha256-<hex>`.
    static func ollamaModels(in dir: String) -> [OllamaModel] {
        let root = dir + "/manifests"
        guard let walker = FileManager.default.enumerator(atPath: root) else { return [] }
        var models: [OllamaModel] = []
        for case let relative as String in walker {
            var parts = relative.split(separator: "/").map(String.init)
            guard parts.count >= 2, !parts.contains(where: { $0.hasPrefix(".") }),
                  let data = FileManager.default.contents(atPath: root + "/" + relative),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            var layers = json["layers"] as? [[String: Any]] ?? []
            if let config = json["config"] as? [String: Any] { layers.append(config) }
            var blobs: [String: Int64] = [:]
            for layer in layers {
                guard let digest = layer["digest"] as? String else { continue }
                let blob = dir + "/blobs/" + digest.replacingOccurrences(of: ":", with: "-")
                if let size = fileSize(blob) { blobs[blob] = size }
            }
            // The official library is implied, as in `ollama list`.
            let tag = parts.removeLast()
            if parts.first == "registry.ollama.ai" {
                parts.removeFirst()
                if parts.first == "library" { parts.removeFirst() }
            }
            models.append(OllamaModel(name: parts.joined(separator: "/") + ":" + tag,
                                      manifest: root + "/" + relative, blobs: blobs))
        }
        return models
    }

    /// The blobs nothing references any more once the `removing` manifests are gone.
    /// Used for the "selected" size (from the scan) and for the trash plan (from disk).
    static func releasedBlobs(removing: Set<String>,
                              models: [(manifest: String, blobs: [String: Int64])]) -> [String: Int64] {
        var kept = Set<String>()
        var released: [String: Int64] = [:]
        for model in models where !removing.contains(model.manifest) { kept.formUnion(model.blobs.keys) }
        for model in models where removing.contains(model.manifest) {
            for (blob, bytes) in model.blobs where !kept.contains(blob) { released[blob] = bytes }
        }
        return released
    }

    private static func scanOllama(_ dir: String, tool: AITool) -> (items: [AIItem], shared: Int64) {
        let models = ollamaModels(in: dir)
        var unique: [String: Int64] = [:]
        var items = models.map { model -> AIItem in
            unique.merge(model.blobs) { first, _ in first }
            let bytes = model.blobs.values.reduce(0, +) + (fileSize(model.manifest) ?? 0)
            return AIItem(id: tool.id + ":" + model.manifest, toolID: tool.id, name: model.name, kind: .models,
                          bytes: bytes, files: model.blobs.count + 1, date: created(model.manifest),
                          paths: [model.manifest], ollamaDir: dir, blobs: model.blobs)
        }
        let counted = models.reduce(Int64(0)) { $0 + $1.blobs.values.reduce(0, +) }
        let shared = counted - unique.values.reduce(0, +)

        // Blobs no manifest points at: interrupted pulls and leftovers of removed models.
        let orphans = entries(in: dir + "/blobs", depth: 1).filter { unique[$0] == nil }
        let orphanBytes = orphans.compactMap(fileSize).reduce(0, +)
        if orphanBytes > 0 {
            items.append(AIItem(id: tool.id + ":orphans:" + dir, toolID: tool.id,
                                name: "Unfinished and orphaned downloads", kind: .cache, bytes: orphanBytes,
                                files: orphans.count, date: nil, paths: orphans))
        }
        return (items, shared)
    }

    // MARK: - Trash plan

    /// The exact paths "Move to Trash" trashes for `items`. For Ollama models:
    /// each manifest plus the blobs no remaining manifest references, read fresh from disk.
    static func trashPlan(for items: [AIItem]) -> [String] {
        var plan = items.filter { $0.ollamaDir == nil }.flatMap(\.paths)
        let stores = Dictionary(grouping: items.filter { $0.ollamaDir != nil }) { $0.ollamaDir ?? "" }
        for (dir, selected) in stores.sorted(by: { $0.key < $1.key }) {
            let removing = Set(selected.flatMap(\.paths))
            let onDisk = ollamaModels(in: dir).map { (manifest: $0.manifest, blobs: $0.blobs) }
            plan += removing.sorted()
            plan += releasedBlobs(removing: removing, models: onDisk).keys.sorted()
        }
        return plan
    }

    /// Bytes that trashing `selected` frees, given everything the scan found
    /// (an Ollama blob another model still needs stays, so it is not counted).
    static func freedBytes(selected: [AIItem], among all: [AIItem]) -> Int64 {
        var total = selected.filter { $0.ollamaDir == nil }.reduce(Int64(0)) { $0 + $1.bytes }
        let chosen = selected.filter { $0.ollamaDir != nil }
        guard !chosen.isEmpty else { return total }
        // A model's own bytes minus its blobs is its manifest.
        total += chosen.reduce(Int64(0)) { $0 + $1.bytes - $1.blobs.values.reduce(0, +) }
        let models = all.filter { $0.ollamaDir != nil }.map { (manifest: $0.paths[0], blobs: $0.blobs) }
        total += releasedBlobs(removing: Set(chosen.map { $0.paths[0] }), models: models).values.reduce(0, +)
        return total
    }

    /// Last line of defence before anything is trashed: inside `home`, and never
    /// a folder that other apps share.
    static func isSafeToTrash(_ path: String, home: String) -> Bool {
        let root = (home as NSString).standardizingPath
        let target = (path as NSString).standardizingPath
        guard target.hasPrefix(root + "/") else { return false }
        let relative = String(target.dropFirst(root.count + 1))
        let sharedFolders: Set<String> = [
            "Library", "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Group Containers", "Library/Logs", "Library/Preferences", ".cache", ".config",
            ".local", ".local/share", ".docker", "Documents", "Desktop", "Downloads", "Applications",
        ]
        return !relative.isEmpty && !sharedFolders.contains(relative)
    }

    // MARK: - Paths

    /// Folders macOS asks the user about before an app may read them.
    static func isProtected(_ path: String, home: String) -> Bool {
        ["/Library/Containers", "/Library/Group Containers", "/Documents", "/Desktop", "/Downloads"]
            .contains { path == home + $0 || path.hasPrefix(home + $0 + "/") }
    }

    private static func expand(_ path: String, home: String) -> String {
        path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }

    /// Existing paths for a catalog pattern; a trailing `*` matches by prefix.
    private static func resolve(_ pattern: String, home: String) -> [String] {
        let path = expand(pattern, home: home)
        guard path.hasSuffix("*") else {
            return FileManager.default.fileExists(atPath: path) ? [path] : []
        }
        let parent = (path as NSString).deletingLastPathComponent
        let prefix = String((path as NSString).lastPathComponent.dropLast())
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { parent + "/" + $0 }
    }

    private static func roots(of source: AISource) -> [String] {
        switch source.shape {
        case .paths(let patterns): return patterns
        case .each(let dir, _, _, _): return [dir]
        case .rest(let dir): return [dir]
        case .ollama(let dir): return [dir]
        }
    }

    private static func claimedPaths(home: String, fullDiskAccess: Bool) -> Set<String> {
        var claimed = Set<String>()
        for source in tools.flatMap(\.sources) {
            switch source.shape {
            case .rest: continue
            case .paths(let patterns):
                // Listing a guarded folder to expand a pattern would raise the system prompt.
                for pattern in patterns
                where fullDiskAccess || !isProtected(expand(pattern, home: home), home: home) {
                    claimed.formUnion(resolve(pattern, home: home))
                }
            case .each(let dir, _, _, _), .ollama(let dir):
                claimed.insert(expand(dir, home: home))
            }
        }
        return claimed
    }

    /// Visible entries `depth` levels below `dir`.
    private static func entries(in dir: String, depth: Int) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let paths = names.filter { !$0.hasPrefix(".") }.sorted().map { dir + "/" + $0 }
        guard depth > 1 else { return paths }
        return paths.filter(isDirectory).flatMap { entries(in: $0, depth: depth - 1) }
    }

    /// What is left of `dir` once claimed paths are taken out, as the shallowest
    /// paths that contain nothing claimed.
    private static func unclaimed(in dir: String, claimed: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var result: [String] = []
        for name in names.sorted() where name != ".DS_Store" {
            let path = dir + "/" + name
            if claimed.contains(path) { continue }
            if claimed.contains(where: { $0.hasPrefix(path + "/") }) {
                result += unclaimed(in: path, claimed: claimed)
            } else {
                result.append(path)
            }
        }
        return result
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func fileSize(_ path: String) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private static func created(_ path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.creationDate] ?? attributes?[.modificationDate]) as? Date
    }

    /// Regular files under `paths`, counted up to `fileCountCap`.
    private static func fileCount(_ paths: [String]) -> Int {
        var count = 0
        for path in paths {
            guard isDirectory(path) else { count += 1; continue }
            let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: path),
                                                        includingPropertiesForKeys: [.isRegularFileKey])
            while let url = walker?.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { count += 1 }
                if count >= fileCountCap { return fileCountCap }
            }
        }
        return min(count, fileCountCap)
    }
}
