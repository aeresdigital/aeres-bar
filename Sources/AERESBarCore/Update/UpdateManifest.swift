import Foundation

/// What the release feed says about the newest build: `update.json`, written by
/// `scripts/make_update.sh` in the release workflow next to `AERES-Bar.zip`.
public struct UpdateManifest: Codable, Equatable, Sendable {
    /// "1.0.42", shown to people.
    public var version: String
    /// The build number (commits on `main`): what decides "newer".
    public var build: Int
    /// What changed, in Markdown.
    public var notes: String
    /// The zip with the app.
    public var url: URL
    /// Base64 Ed25519 signature of the zip.
    public var signature: String
    /// "14.0": older systems are not offered this build.
    public var minimumSystemVersion: String?

    public init(version: String, build: Int, notes: String, url: URL, signature: String, minimumSystemVersion: String? = nil) {
        self.version = version
        self.build = build
        self.notes = notes
        self.url = url
        self.signature = signature
        self.minimumSystemVersion = minimumSystemVersion
    }

    /// A build newer than `build` that runs on `system`.
    public func isUpdate(over build: Int, system: OperatingSystemVersion) -> Bool {
        self.build > build && runs(on: system)
    }

    public func runs(on system: OperatingSystemVersion) -> Bool {
        guard let minimum = minimumSystemVersion else { return true }
        let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        let required = [parts.first ?? 0, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0]
        let running = [system.majorVersion, system.minorVersion, system.patchVersion]
        return !running.lexicographicallyPrecedes(required)
    }

    /// The notes as plain lines, without Markdown marks or blank lines.
    public var releaseNotes: [ReleaseNote] {
        notes.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var text = String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            for bullet in ["- ", "* "] where text.hasPrefix(bullet) { text.removeFirst(bullet.count) }
            text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ReleaseNote(text: text, isHeading: trimmed.hasPrefix("#"))
        }
    }
}

/// A line of the release notes: a section heading ("Novidades") or an item.
public struct ReleaseNote: Equatable, Sendable {
    public var text: String
    public var isHeading: Bool
}
