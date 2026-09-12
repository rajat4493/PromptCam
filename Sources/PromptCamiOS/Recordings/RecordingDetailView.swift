import AVKit
import CoreMedia
import SwiftUI
import PromptCamCore

/// Review one interview: play it, read the marker timeline, export both.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
struct RecordingDetailView: View {
    let recording: InterviewRecordingModel
    let model: RecordingsLibraryModel

    @State private var player: AVPlayer?
    /// Marker files are written once when the screen opens, so each export is a
    /// direct `ShareLink` rather than a tap that has to succeed first.
    @State private var exportURLs: [MarkerExportFormat: URL] = [:]

    var body: some View {
        List {
            playbackSection
            statusSection
            timelineSection
            exportSection
        }
        .navigationTitle(recording.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            preparePlayer()
            prepareExports()
        }
        .onDisappear { player?.pause() }
    }

    // MARK: - Playback

    @ViewBuilder
    private var playbackSection: some View {
        Section {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
            } else {
                // Says exactly why playback is unavailable rather than showing
                // an inert black box.
                Label {
                    Text(unavailableReason)
                } icon: {
                    Image(systemName: "play.slash")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableReason: String {
        if !recording.outcome.isPlayable {
            if recording.preservedFilePath != nil {
                return "This interview did not finish saving, so it cannot be played here. The captured video file has been kept on this device."
            }
            return "This interview did not produce a playable video file."
        }
        return "The video file for this interview could not be found. It may have been removed from the device."
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section("Details") {
            LabeledContent("Status", value: recording.outcome.shortDescription)
            LabeledContent("Recorded", value: recording.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Duration", value: MarkerExporter.timecode(recording.duration))
            LabeledContent("Markers", value: "\(recording.markers.count)")

            if let failure = recording.failureDescription {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.warning)
            }

            if let preserved = recording.preservedFilePath {
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("Kept file").font(.caption.weight(.medium))
                    Text(preserved)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        let rows = model.timelineRows(for: recording)
        Section {
            if rows.isEmpty {
                Text("No markers or question changes were recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Button {
                        seek(to: row.offset)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.regular) {
                            Text(MarkerExporter.shortTimecode(row.offset))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .leading)

                            Image(systemName: row.kind == .marker ? "bookmark.fill" : "text.bubble")
                                .font(.caption)
                                .foregroundStyle(row.kind == .marker ? Theme.Palette.recording : .secondary)

                            Text(row.label)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(player == nil)
                }
            }
        } header: {
            Text("Timeline")
        } footer: {
            if player != nil {
                Text("Tap a row to jump to that moment.")
            }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section("Export") {
            if let videoURL = model.videoURL(for: recording) {
                ShareLink(item: videoURL) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                }
            }

            ForEach(MarkerExportFormat.allCases) { format in
                if let url = exportURLs[format] {
                    ShareLink(item: url) {
                        Label("Markers — \(format.displayName)", systemImage: "list.bullet.rectangle.portrait")
                    }
                } else {
                    // The export could not be written. Says so instead of
                    // offering a share that would fail.
                    Label("Markers — \(format.displayName)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func preparePlayer() {
        guard let url = model.videoURL(for: recording) else {
            player = nil
            return
        }
        player = AVPlayer(url: url)
    }

    /// Writes both marker formats. A failure leaves that format's entry absent,
    /// which the export section renders as unavailable; the recording itself is
    /// untouched either way.
    private func prepareExports() {
        var resolved: [MarkerExportFormat: URL] = [:]
        for format in MarkerExportFormat.allCases {
            if let url = model.exportMarkers(for: recording, format: format) {
                resolved[format] = url
            }
        }
        exportURLs = resolved
    }

    private func seek(to offset: TimeInterval) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
    }
}
