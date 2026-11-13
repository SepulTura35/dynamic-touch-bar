import Combine
import Foundation
import IOKit.ps

nonisolated struct BatteryInfo: Equatable, Sendable {
    var hasBattery: Bool
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isCharged: Bool
    /// Minutes, when macOS has an estimate.
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var adapterWatts: Int?
    var isLowPowerMode: Bool

    static let unknown = BatteryInfo(hasBattery: false, level: 0, isCharging: false, isPluggedIn: true, isCharged: false,
                                     minutesToEmpty: nil, minutesToFull: nil, adapterWatts: nil, isLowPowerMode: false)

    var fraction: Double { Double(level) / 100 }

    var statusText: String {
        guard hasBattery else { return "Power Adapter" }
        if isCharged || (isPluggedIn && level >= 100) { return "Fully Charged" }
        if isCharging {
            if let minutes = minutesToFull { return "\(TimeFormat.duration(minutes: minutes)) to full" }
            return "Charging"
        }
        if isPluggedIn { return "Not Charging" }
        if let minutes = minutesToEmpty { return "\(TimeFormat.duration(minutes: minutes)) left" }
        return "On Battery"
    }

    /// Builds from IOPowerSources descriptions (public `IOKit.ps` keys).
    static func parse(descriptions: [[String: Any]], adapter: [String: Any]?, lowPowerMode: Bool) -> BatteryInfo {
        guard let battery = descriptions.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType })
                ?? descriptions.first(where: { $0[kIOPSCurrentCapacityKey] != nil }) else {
            var info = BatteryInfo.unknown
            info.isLowPowerMode = lowPowerMode
            return info
        }
        let current = (battery[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let maximum = max((battery[kIOPSMaxCapacityKey] as? Int) ?? 100, 1)
        let level = Int((Double(current) / Double(maximum) * 100).rounded()).clamped(0, 100)
        let pluggedIn = (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = (battery[kIOPSIsChargingKey] as? Bool) ?? false
        let charged = (battery[kIOPSIsChargedKey] as? Bool) ?? false
        let toEmpty = (battery[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let toFull = (battery[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let watts = adapter?[kIOPSPowerAdapterWattsKey] as? Int
        return BatteryInfo(
            hasBattery: true,
            level: level,
            isCharging: charging,
            isPluggedIn: pluggedIn,
            isCharged: charged,
            minutesToEmpty: pluggedIn ? nil : toEmpty,
            minutesToFull: charging ? toFull : nil,
            adapterWatts: pluggedIn ? watts : nil,
            isLowPowerMode: lowPowerMode
        )
    }
}

nonisolated enum BatteryEvent: Equatable, Sendable {
    case pluggedIn, unplugged, low(Int), fullyCharged
}

/// Battery state via `IOPSNotificationCreateRunLoopSource` — the system calls us when power
/// state changes; nothing is polled.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var info = BatteryInfo.unknown

    var lowThreshold = 20
    var onEvent: ((BatteryEvent) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?
    private var didWarnLow = false

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.read(emitEvents: true) }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        powerStateObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(emitEvents: false) }
        }
        read(emitEvents: false)
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        if let powerStateObserver { NotificationCenter.default.removeObserver(powerStateObserver) }
        powerStateObserver = nil
    }

    func refresh() { read(emitEvents: false) }

    private func read(emitEvents: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        let descriptions: [[String: Any]] = list.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let next = BatteryInfo.parse(descriptions: descriptions, adapter: adapter, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let previous = info
        guard next != previous else { return }
        info = next
        guard emitEvents, next.hasBattery else { return }
        for event in Self.events(from: previous, to: next, lowThreshold: lowThreshold, alreadyWarned: &didWarnLow) {
            onEvent?(event)
        }
    }

    /// Pure transition logic (unit-tested).
    static func events(from previous: BatteryInfo, to next: BatteryInfo, lowThreshold: Int, alreadyWarned: inout Bool) -> [BatteryEvent] {
        var events: [BatteryEvent] = []
        if next.isPluggedIn && !previous.isPluggedIn { events.append(.pluggedIn) }
        if !next.isPluggedIn && previous.isPluggedIn { events.append(.unplugged) }
        if next.isPluggedIn { alreadyWarned = false }
        if !next.isPluggedIn && next.level <= lowThreshold && !alreadyWarned {
            alreadyWarned = true
            events.append(.low(next.level))
        }
        let nowFull = next.isCharged || (next.isPluggedIn && next.level >= 100)
        let wasFull = previous.isCharged || (previous.isPluggedIn && previous.level >= 100)
        if nowFull && !wasFull && previous.isPluggedIn { events.append(.fullyCharged) }
        return events
    }
}
