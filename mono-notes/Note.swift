import Foundation

struct Note: Identifiable, Codable {
    var id: UUID = UUID()
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// First non-empty line — used as list title
    var title: String {
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first
        guard let line = first else { return "Empty note" }
        let s = String(line)
        return s.count > 60 ? String(s.prefix(60)) + "\u{2026}" : s
    }

    /// Second line onwards — used as list preview
    var preview: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return "" }
        let rest = lines.dropFirst().joined(separator: " ")
        return rest.count > 80 ? String(rest.prefix(80)) + "\u{2026}" : rest
    }

    /// Formatted date label for list
    var dateLabel: String {
        let df = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            df.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(updatedAt) {
            return "yesterday"
        } else {
            df.dateFormat = "dd.MM.yy"
        }
        return df.string(from: updatedAt)
    }
}
