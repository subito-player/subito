import Foundation

// Editor times: "m:ss", "m:ss.f" or plain seconds; a comma works as the decimal mark too.
public enum Clock {
    public static func seconds(from text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard let last = parts.last, let seconds = Double(last), seconds.isFinite, seconds >= 0 else { return nil }
        switch parts.count {
        case 1:
            return seconds
        case 2:
            guard let minutes = Int(parts[0]), minutes >= 0, seconds < 60 else { return nil }
            return Double(minutes) * 60 + seconds
        default:
            return nil
        }
    }

    // Milliseconds survive, so a field shown and committed unchanged never moves a marker.
    public static func text(_ seconds: Double) -> String {
        let millis = seconds.isFinite ? Int((min(max(seconds, 0), 359_999) * 1000).rounded()) : 0
        let whole = millis / 1000
        var text = String(format: "%ld:%02ld", whole / 60, whole % 60)
        if millis % 1000 > 0 {
            var fraction = String(format: "%03ld", millis % 1000)
            while fraction.hasSuffix("0") { fraction.removeLast() }
            text += "." + fraction
        }
        return text
    }
}
