import Foundation

/// Incremental reader for append-only JSONL logs. It remembers how far each file was read,
/// so after the first pass a refresh only touches the bytes written since.
///
/// Not thread-safe: each instance is owned by one provider actor.
final class JSONLTailReader {
    private var offsets: [String: UInt64] = [:]
    private let chunkSize: Int

    init(chunkSize: Int = 4 << 20) {
        self.chunkSize = max(chunkSize, 1)
    }

    /// Forgets files that are no longer of interest (deleted or too old).
    func prune(keeping paths: Set<String>) {
        offsets = offsets.filter { paths.contains($0.key) }
    }

    /// Feeds each complete new line that contains one of `needles` to `body`.
    /// A trailing line without a newline is left for the next call: it may still be being written.
    func readNewLines(
        at path: String,
        fileSize: UInt64,
        needles: [[UInt8]],
        _ body: (UnsafeRawBufferPointer) -> Void
    ) {
        var offset = offsets[path] ?? 0
        if fileSize < offset { offset = 0 }  // rewritten or truncated
        offsets[path] = offset
        guard fileSize > offset else { return }
        let file = open(path, O_RDONLY | O_CLOEXEC)
        guard file >= 0 else { return }
        defer { close(file) }
        guard lseek(file, off_t(offset), SEEK_SET) == off_t(offset), var buffer = MappedBuffer(capacity: chunkSize) else { return }
        defer { buffer.release() }

        // The buffer holds the unfinished line of the previous read (`carried` bytes) followed
        // by what the next read brings.
        var carried = 0
        while true {
            if carried == buffer.capacity, !buffer.grow(keeping: carried) { break }  // a line longer than the buffer
            let count = read(file, buffer.base + carried, buffer.capacity - carried)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }  // end of file, or an error: keep what was read
            let valid = carried + count
            var start = 0
            while start < valid, let newline = memchr(buffer.base + start, 0x0A, valid - start) {
                let end = buffer.base.distance(to: newline)
                let line = UnsafeRawBufferPointer(start: buffer.base + start, count: end - start)
                if needles.contains(where: { Bytes.contains(line, $0) }) { body(line) }
                start = end + 1
            }
            offset += UInt64(start)
            carried = valid - start
            if carried > 0, start > 0 { memmove(buffer.base, buffer.base + start, carried) }
        }
        offsets[path] = offset
    }
}

/// Scratch memory mapped straight from the kernel. Unlike malloc'd blocks, which the allocator
/// keeps cached (and counted in the app's footprint) after they are freed, it goes back to the
/// system as soon as it is released: reading a gigabyte of logs leaves nothing behind.
private struct MappedBuffer {
    private(set) var base: UnsafeMutableRawPointer
    private(set) var capacity: Int

    init?(capacity: Int) {
        guard let base = Self.map(capacity) else { return nil }
        self.base = base
        self.capacity = capacity
    }

    /// Doubles the capacity, keeping the first `count` bytes.
    mutating func grow(keeping count: Int) -> Bool {
        guard let bigger = Self.map(capacity * 2) else { return false }
        memcpy(bigger, base, count)
        munmap(base, capacity)
        base = bigger
        capacity *= 2
        return true
    }

    func release() {
        munmap(base, capacity)
    }

    private static func map(_ size: Int) -> UnsafeMutableRawPointer? {
        guard let pointer = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
            pointer != UnsafeMutableRawPointer(bitPattern: -1)  // MAP_FAILED
        else { return nil }
        return pointer
    }
}

/// Byte-level helpers over raw log lines.
enum Bytes {
    static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        find(haystack, needle) != nil
    }

    static func find(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8], from start: Int = 0) -> Int? {
        guard let base = haystack.baseAddress, !needle.isEmpty, start >= 0,
            haystack.count - start >= needle.count
        else { return nil }
        return needle.withUnsafeBufferPointer { pattern -> Int? in
            guard let hit = memmem(base + start, haystack.count - start, pattern.baseAddress, pattern.count) else {
                return nil
            }
            return base.distance(to: UnsafeRawPointer(hit))
        }
    }

    static func equals(_ buffer: UnsafeRawBufferPointer, _ range: Range<Int>, _ literal: [UInt8]) -> Bool {
        guard range.count == literal.count, let base = buffer.baseAddress else { return false }
        return literal.withUnsafeBufferPointer { memcmp(base + range.lowerBound, $0.baseAddress, literal.count) == 0 }
    }

    static func string(_ buffer: UnsafeRawBufferPointer, _ range: Range<Int>) -> String {
        String(decoding: UnsafeRawBufferPointer(rebasing: buffer[range]), as: UTF8.self)
    }

    static func data(_ buffer: UnsafeRawBufferPointer, _ range: Range<Int>) -> Data {
        guard let base = buffer.baseAddress else { return Data() }
        return Data(bytes: base + range.lowerBound, count: range.count)
    }
}

/// Walks a JSON object one level deep and reports where each member's key and value sit,
/// without parsing the values. Claude transcripts carry large tool payloads in every
/// assistant line; this pulls out the few fields needed without decoding the rest.
enum ShallowJSON {
    static func members(
        of buffer: UnsafeRawBufferPointer,
        objectAt start: Int,
        _ visit: (_ key: Range<Int>, _ value: Range<Int>) -> Void
    ) {
        let count = buffer.count
        guard start < count, buffer[start] == UInt8(ascii: "{") else { return }
        var index = start + 1
        while true {
            index = skipWhitespace(buffer, index)
            guard index < count, buffer[index] == UInt8(ascii: "\""),
                let keyEnd = endOfString(buffer, index)
            else { return }
            let key = (index + 1)..<(keyEnd - 1)
            index = skipWhitespace(buffer, keyEnd)
            guard index < count, buffer[index] == UInt8(ascii: ":") else { return }
            index = skipWhitespace(buffer, index + 1)
            guard let valueEnd = endOfValue(buffer, index) else { return }
            visit(key, index..<valueEnd)
            index = skipWhitespace(buffer, valueEnd)
            guard index < count, buffer[index] == UInt8(ascii: ",") else { return }
            index += 1
        }
    }

    /// Contents of a string value without the quotes. Escapes are left as they are.
    static func stringContents(_ buffer: UnsafeRawBufferPointer, _ value: Range<Int>) -> String? {
        guard value.count >= 2, buffer[value.lowerBound] == UInt8(ascii: "\"") else { return nil }
        return Bytes.string(buffer, (value.lowerBound + 1)..<(value.upperBound - 1))
    }

    /// `index` points at an opening quote; returns the position just past the closing one.
    private static func endOfString(_ buffer: UnsafeRawBufferPointer, _ index: Int) -> Int? {
        var cursor = index + 1
        while cursor < buffer.count {
            switch buffer[cursor] {
            case UInt8(ascii: "\\"): cursor += 2
            case UInt8(ascii: "\""): return cursor + 1
            default: cursor += 1
            }
        }
        return nil
    }

    private static func endOfValue(_ buffer: UnsafeRawBufferPointer, _ index: Int) -> Int? {
        guard index < buffer.count else { return nil }
        switch buffer[index] {
        case UInt8(ascii: "\""):
            return endOfString(buffer, index)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return endOfContainer(buffer, index)
        default:
            var cursor = index
            while cursor < buffer.count {
                switch buffer[cursor] {
                case UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x0A, 0x0D, 0x09:
                    return cursor
                default:
                    cursor += 1
                }
            }
            return cursor
        }
    }

    private static func endOfContainer(_ buffer: UnsafeRawBufferPointer, _ index: Int) -> Int? {
        var depth = 0
        var cursor = index
        while cursor < buffer.count {
            switch buffer[cursor] {
            case UInt8(ascii: "\""):
                guard let end = endOfString(buffer, cursor) else { return nil }
                cursor = end
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return cursor + 1 }
            default:
                break
            }
            cursor += 1
        }
        return nil
    }

    private static func skipWhitespace(_ buffer: UnsafeRawBufferPointer, _ index: Int) -> Int {
        var cursor = index
        while cursor < buffer.count {
            switch buffer[cursor] {
            case 0x20, 0x0A, 0x0D, 0x09: cursor += 1
            default: return cursor
            }
        }
        return cursor
    }
}

/// Finds log files worth reading.
enum RecentFiles {
    struct Entry {
        let path: String
        let size: UInt64
    }

    /// `.jsonl` files under `root` modified after `cutoff`.
    static func jsonl(under root: URL, modifiedAfter cutoff: Date, namePrefix: String? = nil) -> [Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }
        var entries: [Entry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if let namePrefix, !url.lastPathComponent.hasPrefix(namePrefix) { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let modified = values.contentModificationDate, modified >= cutoff
            else { continue }
            entries.append(Entry(path: url.path, size: UInt64(values.fileSize ?? 0)))
        }
        return entries
    }
}
