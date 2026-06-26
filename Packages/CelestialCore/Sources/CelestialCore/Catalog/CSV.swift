import Foundation

/// A minimal, allocation-conscious RFC-4180-ish CSV reader.
///
/// Handles double-quoted fields, escaped quotes (`""`), and both LF and CRLF line
/// endings — enough for the HYG catalog, where text fields like `"9Alp CMa"` are
/// quoted. Operates over raw UTF-8 bytes and streams one record at a time so a
/// 30 MB catalog doesn't have to be materialised as a giant array of strings.
enum CSV {
    static func parseRecords(_ data: Data, _ onRecord: ([String]) throws -> Void) rethrows {
        let bytes = [UInt8](data)
        let count = bytes.count

        let quote: UInt8 = 0x22
        let comma: UInt8 = 0x2C
        let lineFeed: UInt8 = 0x0A
        let carriageReturn: UInt8 = 0x0D

        var fields: [String] = []
        var field: [UInt8] = []
        field.reserveCapacity(32)
        var inQuotes = false
        var recordHasContent = false
        var index = 0

        func endField() {
            fields.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }
        func endRecord() throws {
            endField()
            try onRecord(fields)
            fields.removeAll(keepingCapacity: true)
            recordHasContent = false
        }

        while index < count {
            let byte = bytes[index]
            if inQuotes {
                if byte == quote {
                    if index + 1 < count && bytes[index + 1] == quote {
                        field.append(quote); index += 2
                    } else {
                        inQuotes = false; index += 1
                    }
                } else {
                    field.append(byte); index += 1
                }
            } else {
                switch byte {
                case quote:
                    inQuotes = true; recordHasContent = true; index += 1
                case comma:
                    endField(); recordHasContent = true; index += 1
                case lineFeed:
                    try endRecord(); index += 1
                case carriageReturn:
                    try endRecord()
                    index += (index + 1 < count && bytes[index + 1] == lineFeed) ? 2 : 1
                default:
                    field.append(byte); recordHasContent = true; index += 1
                }
            }
        }

        // Flush a final record if the file didn't end with a line break.
        if recordHasContent || !field.isEmpty {
            try endRecord()
        }
    }
}
