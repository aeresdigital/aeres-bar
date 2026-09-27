import Foundation

/// Parses Ollama Cloud's usage endpoint and the local server's API.
public enum OllamaParser {
    /// A model loaded in the local server's memory (`/api/ps`).
    public struct LoadedModel: Equatable, Sendable {
        public var name: String
        public var sizeBytes: Int
        public var vramBytes: Int
    }

    /// `GET https://ollama.com/api/usage`: `limits.session` (5 h) and `limits.weekly`, with `usage`
    /// as a 0–1 fraction. The endpoint does not say when the windows renew.
    public static func parseCloudUsage(_ data: Data) -> [UsageWindow]? {
        guard let root = JSON.object(data), let limits = JSON.dict(root["limits"]) else { return nil }
        let definitions: [(key: String, title: String, seconds: Double)] = [
            ("session", "Sessão (5h)", 5 * 3_600),
            ("weekly", "Semanal", 7 * 86_400),
        ]
        var windows: [UsageWindow] = []
        for definition in definitions {
            guard let window = JSON.dict(limits[definition.key]) else { continue }
            let raw = JSON.double(window["usage"]) ?? 0
            // Documented as a fraction; tolerate a percentage in case that changes. Rounded to
            // hundredths so 0.58 reads 58, not 57.99999999999999.
            let percent = ((raw > 1 ? raw : raw * 100) * 100).rounded() / 100
            let requests = (JSON.dict(window["models"]) ?? [:]).values.reduce(0) { $0 + JSON.int(JSON.dict($1)?["request_count"]) }
            windows.append(
                UsageWindow(
                    id: "ollama.\(definition.key)",
                    title: definition.title,
                    subtitle: requests > 0 ? "\(Formatting.count(requests)) \(requests == 1 ? "requisição" : "requisições")" : nil,
                    usedPercent: min(max(percent, 0), 100),
                    windowSeconds: definition.seconds,
                    isPrimary: windows.isEmpty
                )
            )
        }
        return windows.isEmpty ? nil : windows
    }

    /// `GET /api/version` → `{"version": "0.12.3"}`.
    public static func parseVersion(_ data: Data) -> String? {
        JSON.object(data).flatMap { JSON.string($0["version"]) }
    }

    /// `GET /api/ps` → models currently loaded.
    public static func parseLoadedModels(_ data: Data) -> [LoadedModel]? {
        guard let root = JSON.object(data) else { return nil }
        return JSON.array(root["models"]).compactMap { model in
            guard let name = JSON.string(model["name"]) ?? JSON.string(model["model"]) else { return nil }
            return LoadedModel(name: name, sizeBytes: JSON.int(model["size"]), vramBytes: JSON.int(model["size_vram"]))
        }
    }
}
