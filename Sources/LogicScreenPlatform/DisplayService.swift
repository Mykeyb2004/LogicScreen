import AppKit
import CoreGraphics
import Darwin
import LogicScreenCore
import OSLog

@MainActor
public final class DisplayService {
    // Undocumented ABI. Never link it eagerly: unsupported systems must still launch.
    private typealias ConfigureEnabled = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
    private let configureEnabled: ConfigureEnabled?
    private let framework: UnsafeMutableRawPointer?
    private let configQueue = DispatchQueue(label: "dev.logicscreen.app.display-config", qos: .userInitiated)
    private let logger = Logger(subsystem: "dev.logicscreen.app", category: "Displays")
    private var remembered: [String: DisplayRecord] = [:]

    public init() {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL)
        framework = handle
        configureEnabled = handle.flatMap { dlsym($0, "CGSConfigureDisplayEnabled") }
            .map { unsafeBitCast($0, to: ConfigureEnabled.self) }
    }

    public var supportsDisconnection: Bool { configureEnabled != nil }

    public func displays() -> [DisplayRecord] {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, NSScreen)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        })
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        var current: [DisplayRecord] = []
        for displayID in ids.prefix(Int(count)) {
            let uuid = Self.identity(for: displayID)
            let old = remembered[uuid]
            let screen = screens[displayID]
            let active = CGDisplayIsActive(displayID) != 0 && screen != nil
            let frame = active ? CGDisplayBounds(displayID) : (old?.frame ?? CGDisplayBounds(displayID))
            let visible = screen.map { WindowPlacement.appKitToQuartz($0.visibleFrame, mainDisplayHeight: mainHeight) }
                ?? old?.visibleFrame ?? frame
            let record = DisplayRecord(id: uuid, displayID: displayID,
                                       name: screen?.localizedName ?? old?.name ?? "显示器 \(displayID)",
                                       frame: frame, visibleFrame: visible,
                                       isMain: CGDisplayIsMain(displayID) != 0,
                                       isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                                       isActive: active, isMirrored: CGDisplayIsInMirrorSet(displayID) != 0)
            remembered[uuid] = record
            current.append(record)
        }
        for old in remembered.values where !current.contains(where: { $0.id == old.id }) {
            current.append(DisplayRecord(id: old.id, displayID: old.displayID, name: old.name,
                                         frame: old.frame, visibleFrame: old.visibleFrame, isMain: false,
                                         isBuiltIn: old.isBuiltIn, isActive: false))
        }
        return current.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            if a.isActive != b.isActive { return a.isActive }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public func setMain(_ targetID: String) async throws {
        let active = displays().filter(\.isActive)
        guard let target = active.first(where: { $0.id == targetID }) else { throw ScreenOperationError.missingDisplay }
        guard !active.contains(where: \.isMirrored) else { throw ScreenOperationError.mirroredDisplays }
        let origins = active.map { (id: $0.displayID, x: Int32($0.frame.minX - target.frame.minX), y: Int32($0.frame.minY - target.frame.minY)) }
        try await transaction { config in
            for item in origins {
                try Self.check(CGConfigureDisplayOrigin(config, item.id, item.x, item.y), action: "设置主屏")
            }
        }
        logger.info("Main display configuration committed")
    }

    public func disconnect(_ ids: Set<String>) async throws {
        let current = displays()
        try DisplaySafety.validateDisconnection(ids: ids, displays: current)
        guard let configureEnabled else { throw ScreenOperationError.unavailable("此系统未提供可用的屏幕停用接口。") }
        let targetDisplayIDs = current.filter { ids.contains($0.id) }.map(\.displayID)
        try await transaction { config in
            for displayID in targetDisplayIDs {
                try Self.checkRaw(configureEnabled(config, displayID, 0), action: "停用屏幕")
            }
        }
        logger.info("Display disconnection committed, count=\(ids.count)")
    }

    public func reconnect(_ record: DisplayRecord) async throws {
        guard let configureEnabled else { throw ScreenOperationError.unavailable("此系统不支持软件重新连接。") }
        let liveID = displays().first(where: { $0.id == record.id })?.displayID ?? record.displayID
        try await transaction { config in
            try Self.checkRaw(configureEnabled(config, liveID, 1), action: "重新连接屏幕")
        }
        logger.info("Display reconnection requested")
    }

    /// Restore only the layout we changed. The persistent system layout is never overwritten.
    public func restore(_ snapshot: [DisplayRecord]) async throws {
        let current = displays()
        let missing = snapshot.filter(\.isActive).filter { saved in !current.contains { $0.id == saved.id && $0.isActive } }
        if !missing.isEmpty, let configureEnabled {
            let reconnectIDs = missing.map { record in
                current.first(where: { $0.id == record.id })?.displayID ?? record.displayID
            }
            try await transaction { config in
                for liveID in reconnectIDs {
                    try Self.checkRaw(configureEnabled(config, liveID, 1), action: "恢复屏幕连接")
                }
            }
        }
        try await restoreOrigins(snapshot)
        logger.info("Original display layout requested")
    }

    public func restoreOrigins(_ snapshot: [DisplayRecord]) async throws {
        let current = displays()
        let origins: [(id: UInt32, x: Int32, y: Int32)] = snapshot.filter(\.isActive).compactMap { saved in
            guard let live = current.first(where: { $0.id == saved.id && $0.isActive }) else { return nil }
            return (id: live.displayID, x: Int32(saved.frame.minX), y: Int32(saved.frame.minY))
        }
        try await transaction { config in
            for item in origins {
                try Self.check(CGConfigureDisplayOrigin(config, item.id, item.x, item.y), action: "恢复屏幕布局")
            }
        }
    }

    public static func identity(for displayID: UInt32) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return "runtime-\(displayID)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Run blocking WindowServer display transactions off the main thread so the main CFRunLoop
    /// stays free to service WindowServer / AppKit display reconfiguration callbacks without deadlocking.
    private func transaction(_ body: @Sendable @escaping (CGDisplayConfigRef) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            configQueue.async {
                var configuration: CGDisplayConfigRef?
                do {
                    try Self.check(CGBeginDisplayConfiguration(&configuration), action: "开始屏幕配置")
                    guard let configuration else {
                        throw ScreenOperationError.unavailable("无法创建屏幕配置。")
                    }
                    do {
                        try body(configuration)
                    } catch {
                        CGCancelDisplayConfiguration(configuration)
                        throw error
                    }
                    // macOS reverts application-scoped changes when this process exits, including after a crash.
                    try Self.check(CGCompleteDisplayConfiguration(configuration, .forAppOnly), action: "应用屏幕配置")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func check(_ error: CGError, action: String) throws {
        try checkRaw(error.rawValue, action: action)
    }

    private nonisolated static func checkRaw(_ result: Int32, action: String) throws {
        guard result == 0 else { throw ScreenOperationError.systemFailure(action, result) }
    }
}
