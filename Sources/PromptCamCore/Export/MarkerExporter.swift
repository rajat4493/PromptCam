import Foundation

/// Renders an interview's markers and question changes into formats a human or
/// an editing tool can use.
///
/// Pure functions over value types, so the output is exactly assertable.
public struct MarkerExporter: Sendable {

    /// One row of the exported timeline.
    public struct Row: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case marker
            case question
        }

        public let offset: TimeInterval
        public let kind: Kind
        public let label: String

        public init(offset: TimeInterval, kind: Kind, label: String) {
            self.offset = offset
            self.kind = kind
            self.label = label
        }
    }

    public init() {}

    /// Merges markers and question changes into one chronological timeline.
    ///
    /// At an identical offset a question sorts before a marker, because the
    /// question was on screen before the operator could flag the moment.
    public func rows(for recording: InterviewRecordingModel) -> [Row] {
        rows(markers: recording.markers, questionChanges: recording.questionChanges)
    }

    public func rows(
        markers: [MarkerModel],
        questionChanges: [QuestionChangeModel]
    ) -> [Row] {
        let markerRows = markers.map {
            Row(offset: $0.offset, kind: .marker, label: $0.label)
        }
        let questionRows = questionChanges.map {
            Row(offset: $0.offset, kind: .question, label: "Q\($0.index + 1): \($0.text)")
        }
        return (questionRows + markerRows).sorted { lhs, rhs in
            if lhs.offset == rhs.offset {
                // Question first at a tie; otherwise keep a stable order.
                if lhs.kind != rhs.kind {
                    return lhs.kind == .question
                }
                return false
            }
            return lhs.offset < rhs.offset
        }
    }

    /// RFC 4180 CSV.
    ///
    /// Every field is quoted and embedded quotes are doubled, so a question
    /// containing a comma, a quotation mark or a newline cannot corrupt a row.
    public func csv(for recording: InterviewRecordingModel) -> String {
        var lines: [String] = ["timecode,seconds,type,label"]
        for row in rows(for: recording) {
            let fields = [
                Self.timecode(row.offset),
                Self.secondsString(row.offset),
                row.kind.rawValue,
                row.label
            ]
            lines.append(fields.map(Self.csvField).joined(separator: ","))
        }
        // Trailing newline so files concatenate cleanly.
        return lines.joined(separator: "\n") + "\n"
    }

    /// Plain text, for a human reading it on a phone.
    public func plainText(for recording: InterviewRecordingModel) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var out = "\(recording.displayTitle)\n"
        out += "Recorded \(formatter.string(from: recording.startedAt))\n"
        out += "Duration \(Self.timecode(recording.duration))\n"
        out += "Status \(recording.outcome.shortDescription)\n"
        out += String(repeating: "-", count: 44) + "\n"

        let allRows = rows(for: recording)
        guard !allRows.isEmpty else {
            out += "No markers or question changes were recorded.\n"
            return out
        }

        for row in allRows {
            let tag = row.kind == .marker ? "MARKER  " : "QUESTION"
            out += "\(Self.timecode(row.offset))  \(tag)  \(row.label)\n"
        }
        return out
    }

    /// Suggested filename stem, with no extension.
    public func fileNameStem(for recording: InterviewRecordingModel) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: recording.startedAt)
        let safeTitle = recording.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = safeTitle.isEmpty ? "Interview" : safeTitle
        return "\(stem) \(stamp) markers"
    }

    // MARK: - Formatting

    /// `HH:MM:SS.mmm`, always zero-padded so the column sorts as text.
    ///
    /// Negative offsets clamp to zero: an offset before the start of capture is
    /// meaningless and must not produce a malformed timecode.
    public static func timecode(_ offset: TimeInterval) -> String {
        let clamped = max(0, offset)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    /// `MM:SS`, for the on-screen recording timer.
    public static func shortTimecode(_ offset: TimeInterval) -> String {
        let clamped = max(0, offset)
        let totalSeconds = Int(clamped)
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func secondsString(_ offset: TimeInterval) -> String {
        String(format: "%.3f", max(0, offset))
    }

    static func csvField(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
