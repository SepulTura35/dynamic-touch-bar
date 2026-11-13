import Foundation

/// Opt-in: shows browser downloads that are in progress in ~/Downloads.
///
/// Browsers write partial files with well-known extensions (`.download` for Safari,
/// `.crdownload` for Chromium, `.part` for Firefox). A kqueue-backed `DispatchSource` tells us
/// when the folder changes — no polling while idle. Download *percentages* are not exposed by
/// any public API, so tasks are shown as indeterminate with the bytes received so far.
/// macOS asks the user before the app can read the Downloads folder.
final class DownloadsWatcher {
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    private let progress: ProgressCenter
    private var source: DispatchSourceFileSystemObject?
    private var sampleTimer: Timer?
    private var known: Set<String> = []
    private let directory: URL

    init(progress: ProgressCenter, directory: URL? = nil) {
        self.progress = progress
        self.directory = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    var isRunning: Bool { source != nil }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard source == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.system.error("Downloads watcher: cannot open folder (permission denied?)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        scan()
    }

    private func stop() {
        source?.cancel()
        source = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        for name in known { progress.cancel(id: Self.taskID(name)) }
        known.removeAll()
    }

    static func taskID(_ name: String) -> String { "download:\(name)" }

    static func isPartial(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func displayName(_ partialName: String) -> String {
        (partialName as NSString).deletingPathExtension
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let partials = Set(names.filter(Self.isPartial))

        for name in partials.subtracting(known) {
            progress.upsert(id: Self.taskID(name), title: Self.displayName(name), fraction: nil,
                            detail: "Downloading", symbol: "arrow.down.circle.fill")
        }
        for name in known.subtracting(partials) {
            let finalName = Self.displayName(name)
            let completed = names.contains(finalName)
            progress.finish(id: Self.taskID(name), success: completed, detail: completed ? "Downloaded" : "Cancelled")
        }
        known = partials
        updateSampling()
    }

    /// While downloads are active, refresh "bytes received" once per second. Stops when idle.
    private func updateSampling() {
        if known.isEmpty {
            sampleTimer?.invalidate()
            sampleTimer = nil
            return
        }
        guard sampleTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
        sample()
    }

    private func sample() {
        for name in known {
            let bytes = Self.size(of: directory.appendingPathComponent(name))
            progress.upsert(id: Self.taskID(name), title: nil, fraction: nil, detail: ByteFormat.string(bytes))
        }
    }

    private static func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        // Safari's .download is a bundle directory.
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }
}
