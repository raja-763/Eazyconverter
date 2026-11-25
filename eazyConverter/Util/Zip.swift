import Foundation
import Compression

/// Minimal ZIP support for reading and writing .docx files.
/// Apple has no public ZIP API, so this uses the Compression framework
/// (raw DEFLATE) for reading and writes entries uncompressed ("stored"),
/// which every Word processor accepts.
enum ZipError: Error, LocalizedError {
    case notAZip, corrupt, unsupportedCompression(UInt16)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "This file isn't a valid Word document (it isn't a ZIP package)."
        case .corrupt: return "This Word document appears to be damaged."
        case .unsupportedCompression: return "This Word document uses compression the app can't read."
        }
    }
}

struct ZipReader {
    private let bytes: [UInt8]
    private(set) var entries: [String: (method: UInt16, compSize: Int, size: Int, localOffset: Int)] = [:]

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }

        // Find the End Of Central Directory record (search backwards).
        var eocd = -1
        var i = bytes.count - 22
        let stop = max(0, bytes.count - 22 - 65_535)
        while i >= stop {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4b50 else { throw ZipError.corrupt }
            let method = u16(p + 10)
            let comp = Int(u32(p + 20))
            let size = Int(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let local = Int(u32(p + 42))
            guard p + 46 + nameLen <= bytes.count else { throw ZipError.corrupt }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            entries[name] = (method, comp, size, local)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func data(for name: String) throws -> Data? {
        guard let e = entries[name] else { return nil }
        let p = e.localOffset
        guard p + 30 <= bytes.count, u32(p) == 0x0403_4b50 else { throw ZipError.corrupt }
        let start = p + 30 + Int(u16(p + 26)) + Int(u16(p + 28))
        guard start + e.compSize <= bytes.count else { throw ZipError.corrupt }
        let slice = Array(bytes[start..<(start + e.compSize)])

        switch e.method {
        case 0:
            return Data(slice)
        case 8:
            if e.size == 0 { return Data() }
            var out = [UInt8](repeating: 0, count: e.size)
            let written = slice.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, e.size,
                                              src.baseAddress!, src.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == e.size else { throw ZipError.corrupt }
            return Data(out)
        default:
            throw ZipError.unsupportedCompression(e.method)
        }
    }

    private func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8 }
    private func u32(_ o: Int) -> UInt32 {
        UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
    }
}

struct ZipWriter {
    private var output = [UInt8]()
    private var central = [UInt8]()
    private var count = 0

    mutating func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }

    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = [UInt8](name.utf8)
        let body = [UInt8](data)
        let crc = CRC32.checksum(body)
        let offset = UInt32(output.count)

        // Local file header
        Self.put32(&output, 0x0403_4b50); Self.put16(&output, 20); Self.put16(&output, 0); Self.put16(&output, 0)
        Self.put16(&output, 0); Self.put16(&output, 33)               // time, date (1980-01-01)
        Self.put32(&output, crc); Self.put32(&output, UInt32(body.count)); Self.put32(&output, UInt32(body.count))
        Self.put16(&output, UInt16(nameBytes.count)); Self.put16(&output, 0)
        output += nameBytes
        output += body

        // Central directory entry
        Self.put32(&central, 0x0201_4b50); Self.put16(&central, 20); Self.put16(&central, 20); Self.put16(&central, 0)
        Self.put16(&central, 0); Self.put16(&central, 0); Self.put16(&central, 33)
        Self.put32(&central, crc); Self.put32(&central, UInt32(body.count)); Self.put32(&central, UInt32(body.count))
        Self.put16(&central, UInt16(nameBytes.count)); Self.put16(&central, 0); Self.put16(&central, 0)
        Self.put16(&central, 0); Self.put16(&central, 0); Self.put32(&central, 0)
        Self.put32(&central, offset)
        central += nameBytes
        count += 1
    }

    func finish() -> Data {
        var result = output
        let cdOffset = UInt32(result.count)
        result += central
        Self.put32(&result, 0x0605_4b50); Self.put16(&result, 0); Self.put16(&result, 0)
        Self.put16(&result, UInt16(count)); Self.put16(&result, UInt16(count))
        Self.put32(&result, UInt32(central.count)); Self.put32(&result, cdOffset)
        Self.put16(&result, 0)
        return Data(result)
    }

    private static func put16(_ a: inout [UInt8], _ v: UInt16) { a += [UInt8(v & 0xff), UInt8(v >> 8)] }
    private static func put32(_ a: inout [UInt8], _ v: UInt32) {
        a += [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
