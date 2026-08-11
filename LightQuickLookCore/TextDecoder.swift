import Foundation
import Darwin

public enum TextEncoding: String, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian, windows1252
}

public enum TextDecodeError: Error, Equatable, Sendable {
    case binary
    case unsupportedEncoding
}

public struct DecodedText: Equatable, Sendable {
    public let text: String
    public let encoding: TextEncoding
    public init(text: String, encoding: TextEncoding) { self.text = text; self.encoding = encoding }
}

public enum TextDecoder {
    public static func decode(_ data: Data) throws -> DecodedText {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else { throw TextDecodeError.unsupportedEncoding }
            return DecodedText(text: text, encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else { throw TextDecodeError.unsupportedEncoding }
            return DecodedText(text: text, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else { throw TextDecodeError.unsupportedEncoding }
            return DecodedText(text: text, encoding: .utf16BigEndian)
        }
        if looksBinary(data) { throw TextDecodeError.binary }
        if let text = String(data: data, encoding: .utf8) { return DecodedText(text: text, encoding: .utf8) }
        if let text = String(data: data, encoding: .windowsCP1252) { return DecodedText(text: text, encoding: .windows1252) }
        throw TextDecodeError.unsupportedEncoding
    }

    public static func looksBinary(_ data: Data) -> Bool {
        let sample = data.prefix(8_192)
        guard !sample.isEmpty else { return false }
        var suspicious = 0
        for byte in sample {
            if byte == 0 { return true }
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) { suspicious += 1 }
        }
        return suspicious * 20 > sample.count
    }
}

public enum PreviewPolicy {
    public static let initialChunkBytes = 256 * 1_024
    public static let processingChunkBytes = 256 * 1_024
    public static let eagerFileBytes = 2 * 1_024 * 1_024
    public static let maximumPreviewBytes = 8 * 1_024 * 1_024
}

public struct PreviewDocument: Sendable {
    public let text: String
    public let language: SourceLanguage
    public let fileSize: UInt64
    public let isTruncated: Bool
    public let encoding: TextEncoding
}

public enum PreviewFileLoader {
    public static func load(url: URL) throws -> PreviewDocument {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let size = UInt64(max(Int64(0), metadata.st_size))
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let limit = min(size, UInt64(PreviewPolicy.maximumPreviewBytes))
        var data = Data()
        data.reserveCapacity(Int(limit))
        while data.count < Int(limit) {
            if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) { throw CancellationError() }
            let count = min(PreviewPolicy.processingChunkBytes, Int(limit) - data.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        let decoded = try TextDecoder.decode(data)
        return PreviewDocument(
            text: decoded.text,
            language: LanguageDetector.detect(url: url, prefix: decoded.text),
            fileSize: size,
            isTruncated: size > UInt64(PreviewPolicy.maximumPreviewBytes),
            encoding: decoded.encoding
        )
    }
}
