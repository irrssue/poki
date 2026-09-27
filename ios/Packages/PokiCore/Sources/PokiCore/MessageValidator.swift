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
        value.count <= maximumLength && !value.contains(where: { $0.isNewline })
    }

    public static func remainingCharacters(for value: String) -> Int {
        maximumLength - value.count
    }
}

