import Foundation

/// Startup self-test for the private CoreGraphics / Accessibility / SkyLight symbols the app
/// links via `@_silgen_name`. macOS updates can remove or rename these; probing with `dlsym`
/// at launch lets the app log the breakage and degrade gracefully instead of crashing on
/// first use of a vanished symbol.
final class PrivateAPIHealthCheck: @unchecked Sendable {
    static let shared = PrivateAPIHealthCheck()

    struct Report {
        let missingSymbols: [String]

        var allHealthy: Bool { missingSymbols.isEmpty }
    }

    /// Result of the last `run()`. Empty (healthy) until the check has executed.
    private(set) var report = Report(missingSymbols: [])

    /// Symbols the app declares with @_silgen_name (AppManager.swift, WindowPreviewView.swift,
    /// WindowEnumerationService.swift). Keep in sync when adding new private-API declarations.
    private static let requiredSymbols = [
        "CGSMainConnectionID",
        "CGSGetWindowLevel",
        "CGSHWCaptureWindowList",
        "_AXUIElementGetWindow",
        "_AXUIElementCreateWithRemoteToken",
        "_SLPSSetFrontProcessWithOptions",
        "SLPSPostEventRecordTo",
        "GetProcessForPID",
    ]

    private init() {}

    /// Probes all required private symbols. Cheap (a handful of dlsym lookups) — safe at launch.
    @discardableResult
    func run() -> Report {
        let handle = dlopen(nil, RTLD_NOW)
        let missing = Self.requiredSymbols.filter { dlsym(handle, $0) == nil }
        report = Report(missingSymbols: missing)

        if missing.isEmpty {
            AppLogger.shared.info("Private API health check passed — all \(Self.requiredSymbols.count) symbols present")
        } else {
            AppLogger.shared.error("Private API health check FAILED — missing symbols: \(missing.joined(separator: ", ")). Related features will degrade (window previews, cross-space window detection, z-order filtering).")
        }
        return report
    }
}
