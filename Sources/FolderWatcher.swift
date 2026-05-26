import Foundation

class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let appState: AppState
    private let onNewFile: (URL) -> Void
    private var knownFiles: Set<String>

    init(appState: AppState, onNewFile: @escaping (URL) -> Void) {
        self.appState = appState
        self.onNewFile = onNewFile
        self.knownFiles = Self.currentFiles(in: appState.watchedFolder)
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private static func currentFiles(in folder: URL) -> Set<String> {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(contents.map { $0.lastPathComponent })
    }

    private func startWatching() {
        let path = appState.watchedFolder.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            nil,
            { (_, clientCallBackInfo, _, _, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvent()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func stopWatching() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func handleEvent() {
        let currentFiles = Self.currentFiles(in: appState.watchedFolder)
        let newFiles = currentFiles.subtracting(knownFiles)

        for fileName in newFiles {
            // Skip temporary/partial download files
            if fileName.hasSuffix(".download") || fileName.hasSuffix(".crdownload") || fileName.hasSuffix(".part") || fileName.hasPrefix(".") {
                continue
            }

            let fileURL = appState.watchedFolder.appendingPathComponent(fileName)

            // Brief delay to let the file finish writing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onNewFile(fileURL)
            }
        }

        knownFiles = currentFiles
    }

    func updateWatchedFolder() {
        stopWatching()
        knownFiles = Self.currentFiles(in: appState.watchedFolder)
        startWatching()
    }
}
