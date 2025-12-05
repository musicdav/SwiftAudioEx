import Foundation

final class AudioCacheManager {
    static let shared = AudioCacheManager()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = base.appendingPathComponent("AudioCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func fileURL(for remoteURL: URL, trackId: String? = nil, fileExtension: String? = nil) -> URL {
        let baseName = trackId ?? sha256(remoteURL.absoluteString)
        let resolvedExtension = resolvedFileExtension(for: remoteURL, customFileExtension: fileExtension)
        let name = baseName + "." + resolvedExtension
        return cacheDirectory.appendingPathComponent(name)
    }

    func resolvedFileExtension(for remoteURL: URL, customFileExtension: String?) -> String {
        if let ext = customFileExtension, !ext.isEmpty {
            return ext
        }
        let pathExtension = remoteURL.pathExtension
        return pathExtension.isEmpty ? "dat" : pathExtension
    }

    func write(_ data: Data, to url: URL, offset: UInt64) throws {
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        if #available(iOS 13.0, *) {
            try handle.seek(toOffset: offset)
            handle.write(data)
            try handle.close()
        } else {
            handle.seek(toFileOffset: offset)
            handle.write(data)
            handle.closeFile()
        }
    }

    func read(from url: URL, offset: UInt64, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        do {
            if #available(iOS 13.0, *) {
                try handle.seek(toOffset: offset)
                let data = handle.readData(ofLength: length)
                try handle.close()
                return data.count > 0 ? data : nil
            } else {
                handle.seek(toFileOffset: offset)
                let data = handle.readData(ofLength: length)
                handle.closeFile()
                return data.count > 0 ? data : nil
            }
        } catch {
            return nil
        }
    }

    func fileSize(_ url: URL) -> UInt64 {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
