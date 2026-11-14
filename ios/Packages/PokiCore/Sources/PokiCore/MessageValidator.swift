import Foundation

public enum MessageValidator {
    public static let maximumLength = 30
    public static let maximumCodePoints = 256
    public static let defaultMessage = "Thinking of you"

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func resolvedMessage(from draft: String) -> String {
        let normalized = normalized(draft)
        return normalized.isEmpty ? defaultMessage : normalized
    }

    public static func isValid(_ value: String) -> Bool {
        value.unicodeScalars.count <= maximumCodePoints
            && visibleLength(value) <= maximumLength
            && !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
            && !value.contains(where: { $0.isNewline })
    }

    public static func remainingCharacters(for value: String) -> Int {
        maximumLength - visibleLength(value)
    }

    /// Visible characters as the server counts them (`poki_private.visible_length`).
    /// PostgreSQL cannot segment graphemes, so both sides share this approximation
    /// in the same three passes: pair regional indicators into flags, drop extending
    /// marks, then fold each zero-width-joiner sequence into its first member.
    /// `contracts/message-length.json` keeps the two implementations in agreement.
    public static func visibleLength(_ value: String) -> Int {
        let scalars = Array(value.unicodeScalars).map(\.value)
        var paired: [UInt32] = []
        var index = 0
        while index < scalars.count {
            if isRegionalIndicator(scalars[index]), index + 1 < scalars.count, isRegionalIndicator(scalars[index + 1]) {
                paired.append(0x52)
                index += 2
            } else {
                paired.append(scalars[index])
                index += 1
            }
        }
        let visible = paired.filter { !isExtender($0) }
        var count = 0
        index = 0
        while index < visible.count {
            if visible[index] == 0x200D {
                index += 2
            } else {
                count += 1
                index += 1
            }
        }
        return count
    }

    private static func isRegionalIndicator(_ value: UInt32) -> Bool {
        (0x1F1E6...0x1F1FF).contains(value)
    }

    private static func isExtender(_ value: UInt32) -> Bool {
        switch value {
        case 0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x20D0...0x20FF,
             0xFE00...0xFE0F, 0xFE20...0xFE2F, 0x1F3FB...0x1F3FF,
             0xE0020...0xE007F, 0xE0100...0xE01EF:
            true
        default:
            false
        }
    }
}
