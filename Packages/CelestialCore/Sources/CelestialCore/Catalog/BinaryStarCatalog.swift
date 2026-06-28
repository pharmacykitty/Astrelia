import Foundation

/// Fast loader for the packed binary star catalog (`stars.bin`).
///
/// Text CSV doesn't scale: parsing allocates a `String` per field (hundreds of
/// thousands for a large catalog). The binary format stores fixed-width records of
/// raw little-endian numbers plus a deduplicated string table, so loading is just
/// pointer reads — near-instant and memory-mappable, even at 100k+ stars.
///
/// Layout (little-endian), produced by `Tools/build_star_catalog.py`:
/// ```
/// header:  "AST1" (4)  ·  count: UInt32  ·  recordSize: UInt32
/// record:  id,hip,hd: Int32   (-1 = nil)
///          ra(hours),dec(deg),dist,x,y,z,mag,absmag,ci,lum: Float32 (NaN = nil)
///          properOff,bfOff,conOff,spectOff: UInt32 (0xFFFFFFFF = nil)
/// strings: appended after records; offsets are relative to the table start,
///          each entry = UInt16 byte-length + UTF-8 bytes.
/// ```
public enum BinaryStarCatalog {
    public enum LoadError: Error { case badMagic, truncated }

    public static func parse(_ data: Data) throws -> [Star] {
        try data.withUnsafeBytes { raw throws -> [Star] in
            guard raw.count >= 12,
                  raw.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "A"),
                  raw.load(fromByteOffset: 1, as: UInt8.self) == UInt8(ascii: "S"),
                  raw.load(fromByteOffset: 2, as: UInt8.self) == UInt8(ascii: "T"),
                  raw.load(fromByteOffset: 3, as: UInt8.self) == UInt8(ascii: "1")
            else { throw LoadError.badMagic }

            let count = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let recordSize = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            let recordsStart = 12
            let tableStart = recordsStart + count * recordSize
            guard tableStart <= raw.count else { throw LoadError.truncated }

            // Strings are deduplicated in the file; cache by offset so repeated
            // designations (e.g. constellation codes) are shared in memory too.
            var stringCache: [UInt32: String] = [:]
            func string(at offset: UInt32) -> String? {
                if offset == 0xFFFF_FFFF { return nil }
                if let cached = stringCache[offset] { return cached }
                let p = tableStart + Int(offset)
                guard p + 2 <= raw.count else { return nil }
                let length = Int(raw.loadUnaligned(fromByteOffset: p, as: UInt16.self))
                guard p + 2 + length <= raw.count else { return nil }
                let value = String(decoding: raw[(p + 2)..<(p + 2 + length)], as: UTF8.self)
                stringCache[offset] = value
                return value
            }

            func optInt(_ v: Int32) -> Int? { v == -1 ? nil : Int(v) }
            func optDouble(_ v: Float) -> Double? { v.isNaN ? nil : Double(v) }

            var stars: [Star] = []
            stars.reserveCapacity(count)

            for k in 0..<count {
                let o = recordsStart + k * recordSize
                let id = raw.loadUnaligned(fromByteOffset: o, as: Int32.self)
                let hip = raw.loadUnaligned(fromByteOffset: o + 4, as: Int32.self)
                let hd = raw.loadUnaligned(fromByteOffset: o + 8, as: Int32.self)
                let ra = raw.loadUnaligned(fromByteOffset: o + 12, as: Float.self)
                let dec = raw.loadUnaligned(fromByteOffset: o + 16, as: Float.self)
                let dist = raw.loadUnaligned(fromByteOffset: o + 20, as: Float.self)
                let x = raw.loadUnaligned(fromByteOffset: o + 24, as: Float.self)
                let y = raw.loadUnaligned(fromByteOffset: o + 28, as: Float.self)
                let z = raw.loadUnaligned(fromByteOffset: o + 32, as: Float.self)
                let mag = raw.loadUnaligned(fromByteOffset: o + 36, as: Float.self)
                let absmag = raw.loadUnaligned(fromByteOffset: o + 40, as: Float.self)
                let ci = raw.loadUnaligned(fromByteOffset: o + 44, as: Float.self)
                let lum = raw.loadUnaligned(fromByteOffset: o + 48, as: Float.self)
                let properOff = raw.loadUnaligned(fromByteOffset: o + 52, as: UInt32.self)
                let bfOff = raw.loadUnaligned(fromByteOffset: o + 56, as: UInt32.self)
                let conOff = raw.loadUnaligned(fromByteOffset: o + 60, as: UInt32.self)
                let spectOff = raw.loadUnaligned(fromByteOffset: o + 64, as: UInt32.self)

                let position = x.isNaN ? nil : Vector3(x: Double(x), y: Double(y), z: Double(z))

                stars.append(Star(
                    id: Int(id),
                    hipparcos: optInt(hip),
                    henryDraper: optInt(hd),
                    harvardRevised: nil,
                    gliese: nil,
                    properName: string(at: properOff),
                    bayerFlamsteed: string(at: bfOff),
                    constellation: string(at: conOff),
                    equatorial: EquatorialCoordinates(rightAscension: .hours(Double(ra)),
                                                      declination: .degrees(Double(dec))),
                    distanceParsecs: optDouble(dist),
                    position: position,
                    apparentMagnitude: Double(mag),
                    absoluteMagnitude: optDouble(absmag),
                    spectralType: string(at: spectOff),
                    colorIndex: optDouble(ci),
                    luminosity: optDouble(lum)))
            }
            return stars
        }
    }
}
