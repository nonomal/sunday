import OSLog

enum Logging {
    static let networking = Logger(subsystem: "it.sunday.app", category: "Networking")
    static let uv = Logger(subsystem: "it.sunday.app", category: "UV")
    static let health = Logger(subsystem: "it.sunday.app", category: "Health")
    static let calculator = Logger(subsystem: "it.sunday.app", category: "Calculator")
    static let widget = Logger(subsystem: "it.sunday.app", category: "Widget")
    static let signpost = OSSignposter(subsystem: "it.sunday.app", category: "Signpost")
}

