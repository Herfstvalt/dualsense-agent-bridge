import Foundation

/// Why a profile file could not be turned into bindings.
public enum ProfileLoadError: Error, Hashable, Sendable, CustomStringConvertible {
    case unreadable(path: String, reason: String)
    case invalid(path: String, reason: String)

    public var description: String {
        switch self {
        case .unreadable(let path, let reason):
            #"Could not read the profile at "\#(path)": \#(reason)"#
        case .invalid(let path, let reason):
            #"The profile at "\#(path)" is not usable: \#(reason)"#
        }
    }
}

/// Loads and validates a profile from disk, falling back to the starter profile.
public struct ProfileLoader: Sendable {
    /// Where users are told to keep their profile, relative to the home
    /// directory. Kept relative so no machine-specific path is ever hard-coded.
    public static let defaultRelativePath = ".config/dualsense-bridge/profile.json"

    private let read: @Sendable (String) throws -> Data

    public init() {
        self.init { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    }

    /// Test seam for supplying file contents without touching the file system.
    public init(read: @escaping @Sendable (String) throws -> Data) {
        self.read = read
    }

    /// The absolute default profile path for the current user, if a home
    /// directory is known.
    public static var defaultPath: String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(defaultRelativePath)
            .path
    }

    /// Loads the profile at `path`, or the starter profile when `path` is nil.
    public func load(path: String?) throws -> ControllerProfile {
        guard let path else { return .starterTerminal }

        let data: Data
        do {
            data = try read(path)
        } catch {
            throw ProfileLoadError.unreadable(
                path: path,
                reason: (error as NSError).localizedDescription
            )
        }

        do {
            return try ControllerProfile(decodingJSON: data)
        } catch let error as ProfileValidationError {
            throw ProfileLoadError.invalid(path: path, reason: error.description)
        } catch let error as DecodingError {
            throw ProfileLoadError.invalid(path: path, reason: Self.describe(error))
        }
    }

    /// Loads the default profile path when it exists, otherwise the starter
    /// profile. An explicit path always wins and always reports its errors.
    public func loadPreferringDefaultLocation(path: String?) throws -> ControllerProfile {
        if let path { return try load(path: path) }
        let candidate = Self.defaultPath
        guard FileManager.default.fileExists(atPath: candidate) else { return .starterTerminal }
        return try load(path: candidate)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            context.debugDescription
        case .keyNotFound(let key, _):
            #"Missing required field "\#(key.stringValue)"."#
        case .typeMismatch(let type, let context):
            "Expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        case .valueNotFound(let type, let context):
            "Missing \(type) value at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        @unknown default:
            "The file is not valid profile JSON."
        }
    }
}
