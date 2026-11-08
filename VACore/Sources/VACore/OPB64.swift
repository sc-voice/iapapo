/// Order-preserving base64 in the nf alphabet: the same encoding as `toOrderPreservingBase64` in
/// nx-nameforma's `uuid64.ts`, and `opb64` in `scripts/nfhash.py`.
///
/// Characters sort in the same order as the bytes they encode, so a timeId prefix sorts chronologically.
public enum OPB64 {
    /// 0-9, A-Z, a-z, then `-` and `_`: the value of each character is its index here.
    public static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")

    /// Encodes bytes with 6 bits per character, most significant bit first. A final partial group is
    /// zero-padded on the right, and there is no `=` padding.
    ///
    /// - Parameter bytes: the bytes to encode.
    /// - Returns: the encoded string, 4 characters per 3 bytes, rounded up.
    public static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        var bits: UInt64 = 0
        var count = 0
        for byte in bytes {
            bits = (bits << 8) | UInt64(byte)
            count += 8
            while count >= 6 {
                count -= 6
                out.append(alphabet[Int((bits >> UInt64(count)) & 0x3F)])
            }
        }
        if count > 0 {
            out.append(alphabet[Int((bits << UInt64(6 - count)) & 0x3F)])
        }
        return out
    }
}
