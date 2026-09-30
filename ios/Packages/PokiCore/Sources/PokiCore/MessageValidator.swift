import Foundation

public enum MessageValidator {
    public static let maximumLength = 30
    public static let defaultMessage = "Thinking of you"

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func resolvedMessage(from draft: String) -> String {
        let normalized = normalized(draft)
        return normalized.isEmpty ? defaultMessage : normalized
    }

    public static func isValid(_ value: String) -> Bool {
        value.unicodeScalars.count <= maximumLength && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0.value != 0x200D }) && !value.contains(where: { $0.isNewline })
    }

    public static func remainingCharacters(for value: String) -> Int {
        maximumLength - value.unicodeScalars.count
    }
}

