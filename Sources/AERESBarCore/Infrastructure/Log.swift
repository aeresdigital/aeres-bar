import os

/// Unified-logging categories. Read with:
/// `log stream --predicate 'subsystem == "com.aeresdigital.aeresbar"'`
public enum Log {
    public static let subsystem = "com.aeresdigital.aeresbar"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let providers = Logger(subsystem: subsystem, category: "providers")
    public static let statusBar = Logger(subsystem: subsystem, category: "statusbar")
}
