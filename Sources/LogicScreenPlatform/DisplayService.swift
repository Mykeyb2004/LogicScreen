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

    public func setMain(_ targetID: String) throws {
        let active = displays().filter(\.isActive)
        guard let target = active.first(where: { $0.id == targetID }) else { throw ScreenOperationError.missingDisplay }
        guard !active.contains(where: \.isMirrored) else { throw ScreenOperationError.mirroredDisplays }
        try transaction { config in
            for display in active {
                try check(CGConfigureDisplayOrigin(config, display.displayID,
                                                   Int32(display.frame.minX - target.frame.minX),
                                                   Int32(display.frame.minY - target.frame.minY)), action: "设置主屏")
            }
        }
        logger.info("Main display configuration committed")
    }

    public func disconnect(_ ids: Set<String>) throws {
        let current = displays()
        try DisplaySafety.validateDisconnection(ids: ids, displays: current)
        guard let configureEnabled else { throw ScreenOperationError.unavailable("此系统未提供可用的屏幕停用接口。") }
        try transaction { config in
            for display in current where ids.contains(display.id) {
                try checkRaw(configureEnabled(config, display.displayID, 0), action: "停用屏幕")
            }
        }
        logger.info("Display disconnection committed, count=\(ids.count)")
    }

    public func reconnect(_ record: DisplayRecord) throws {
        guard let configureEnabled else { throw ScreenOperationError.unavailable("此系统不支持软件重新连接。") }
        let liveID = displays().first(where: { $0.id == record.id })?.displayID ?? record.displayID
        try transaction { config in
            try checkRaw(configureEnabled(config, liveID, 1), action: "重新连接屏幕")
        }
        logger.info("Display reconnection requested")
    }

    /// Restore only the layout we changed. The persistent system layout is never overwritten.
    public func restore(_ snapshot: [DisplayRecord]) throws {
        let current = displays()
        let missing = snapshot.filter(\.isActive).filter { saved in !current.contains { $0.id == saved.id && $0.isActive } }
        if !missing.isEmpty, let configureEnabled {
            try transaction { config in
                for record in missing {
                    let liveID = current.first(where: { $0.id == record.id })?.displayID ?? record.displayID
                    try checkRaw(configureEnabled(config, liveID, 1), action: "恢复屏幕连接")
                }
            }
        }
        try restoreOrigins(snapshot)
        logger.info("Original display layout requested")
    }

    public func restoreOrigins(_ snapshot: [DisplayRecord]) throws {
        let current = displays()
        try transaction { config in
            for saved in snapshot where saved.isActive {
                guard let live = current.first(where: { $0.id == saved.id && $0.isActive }) else { continue }
                try check(CGConfigureDisplayOrigin(config, live.displayID,
                                                   Int32(saved.frame.minX), Int32(saved.frame.minY)), action: "恢复屏幕布局")
            }
        }
    }

    public static func identity(for displayID: UInt32) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return "runtime-\(displayID)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func transaction(_ body: (CGDisplayConfigRef) throws -> Void) throws {
        var configuration: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configuration), action: "开始屏幕配置")
        guard let configuration else { throw ScreenOperationError.unavailable("无法创建屏幕配置。") }
        do { try body(configuration) }
        catch { CGCancelDisplayConfiguration(configuration); throw error }
        // macOS reverts application-scoped changes when this process exits, including after a crash.
        try check(CGCompleteDisplayConfiguration(configuration, .forAppOnly), action: "应用屏幕配置")
    }

    private func check(_ error: CGError, action: String) throws {
        try checkRaw(error.rawValue, action: action)
    }

    private func checkRaw(_ result: Int32, action: String) throws {
        guard result == 0 else { throw ScreenOperationError.systemFailure(action, result) }
    }
}
