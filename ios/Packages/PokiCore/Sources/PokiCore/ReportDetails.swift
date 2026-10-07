import Foundation

/// Optional report details are reviewed as a single line, matching the database check.
public enum ReportDetails {
    public static let maximumLength = 300

    public static func normalized(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isValid(_ value: String) -> Bool {
        normalized(value).unicodeScalars.count <= maximumLength
    }

    public static func remainingCharacters(for value: String) -> Int {
        maximumLength - normalized(value).unicodeScalars.count
    }
}
