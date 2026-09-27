import Foundation

/// Identity of the running build.
public enum AppInfo {
    public static let name = "AERES Bar"
    public static let bundleIdentifier = "com.aeresdigital.aeresbar"

    /// `CFBundleShortVersionString`, or "dev" when running outside the app bundle (e.g. `swift run`).
    public static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    /// `CFBundleVersion`, or "0" outside the app bundle.
    public static let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    /// Sent to provider APIs so requests are identifiable.
    public static var userAgent: String { "AERESBar/\(version)" }
}
