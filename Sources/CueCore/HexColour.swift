import Foundation

// Show file colours: "#RRGGBB" or "#RGB", any case, "#" optional; packed as 0xRRGGBB.
public enum HexColour {
    public static func rgb(from text: String) -> UInt32? {
        let digits = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
        // The digit check also keeps out the sign UInt32(_:radix:) would take.
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : String(digits), radix: 16)
    }
}
