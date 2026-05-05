import SwiftUI
import RandomWalkerCore

struct RandomWalkerWatchRootView: View {
    @StateObject private var coordinator = WatchWalkCoordinator()

    var body: some View {
        NavigationStack {
            if let snapshot = coordinator.snapshot {
                WatchRouteView(
                    snapshot: snapshot,
                    isRecordingGPS: coordinator.isRecordingGPS,
                    isWatchGPSGuidanceActive: coordinator.isWatchGPSGuidanceActive,
                    liveStepIndex: coordinator.watchNavigationStepIndex,
                    distanceToManeuverMeters: coordinator.distanceToCurrentManeuverMeters,
                    isSyncedRouteCuesFinishedOnWatch: coordinator.isSyncedRouteCuesFinishedOnWatch
                )
            } else {
                ContentUnavailableView(
                    "No active loop",
                    systemImage: "arrow.trianglehead.merge",
                    description: Text(coordinator.status)
                )
                .padding()
            }
        }
        .task {
            coordinator.activate()
        }
    }
}

private struct WatchRouteView: View {
    let snapshot: ActiveWalkSnapshot
    var isRecordingGPS: Bool
    var isWatchGPSGuidanceActive: Bool
    var liveStepIndex: Int
    var distanceToManeuverMeters: Double?
    var isSyncedRouteCuesFinishedOnWatch: Bool

    @State private var manualStepIndex: Int = 0

    private var isLiveNavigationSession: Bool {
        snapshot.navigationSessionId != nil
    }

    /// Step row shown when browsing a planned route, or when maneuver data prevents Watch GPS cues.
    private var manualDisplayedIndex: Int {
        guard !snapshot.legs.isEmpty else { return 0 }
        return min(max(manualStepIndex, 0), snapshot.legs.count - 1)
    }

    private var cueIndexShown: Int {
        if isWatchGPSGuidanceActive {
            guard !snapshot.legs.isEmpty else { return 0 }
            return min(max(liveStepIndex, 0), snapshot.legs.count - 1)
        }
        return manualDisplayedIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow

            recordingRow

            if isSyncedRouteCuesFinishedOnWatch, isLiveNavigationSession {
                Text(snapshot.legs.last?.title ?? "You're through the synced cues.")
                    .font(.body)
                    .minimumScaleFactor(0.68)
                    .foregroundStyle(.secondary)
                Text("Finish on iPhone if you still expect turns—or complete the loop.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if snapshot.legs.isEmpty {
                Text("No written cues synced—recording still runs for History.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isLiveNavigationSession, isWatchGPSGuidanceActive {
                gpsGuidanceSection
            } else {
                manualBrowseSection
            }
        }
        .navigationTitle("Walk")
        .padding(.vertical, 4)
        .onChange(of: snapshot.routeId) { _, _ in
            manualStepIndex = 0
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        HStack {
            Text("\(Self.displayMinutes(fromSeconds: snapshot.expectedDurationSeconds)) min est.")
                .font(.headline)
            Spacer()
            Text("\(Self.displayMetersRounded(snapshot.totalDistanceMeters)) m")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recordingRow: some View {
        if isRecordingGPS {
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.red)
                Text(isWatchGPSGuidanceActive ? "Navigating & recording path" : "Recording path")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gpsGuidanceSection: some View {
        Group {
            Text("Cue \(cueIndexShown + 1) / \(snapshot.legs.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(snapshot.legs[cueIndexShown].title)
                .font(.body)
                .minimumScaleFactor(0.62)
                .fontWeight(.semibold)

            if let meters = distanceToManeuverMeters {
                distanceLabelLine(meters: meters)
            } else {
                Text("\(Self.displayMetersRounded(snapshot.legs[cueIndexShown].distanceMeters)) m this step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cueIndexShown + 1 < snapshot.legs.count {
                let nextTitle = snapshot.legs[cueIndexShown + 1].title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nextTitle.isEmpty {
                    Text("Then \(nextTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    /// Formats approximate distance remaining to maneuver (dynamic from Watch GPS vs static Maps step distance).
    @ViewBuilder
    private func distanceLabelLine(meters: Double) -> some View {
        if meters.isFinite, meters >= 0 {
            let rounded = round(meters)
            let text: String =
                if rounded >= 1_000 {
                    String(format: "%.1f km to maneuver", rounded / 1_000)
                } else {
                    "\(Int(rounded)) m to maneuver"
                }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Distance unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var manualBrowseSection: some View {
        Group {
            Text("Tap Back / Next • sync app for cue-by-cue GPS on Watch")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text("Cue \(manualDisplayedIndex + 1) / \(snapshot.legs.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(snapshot.legs[manualDisplayedIndex].title)
                .font(.body)
                .minimumScaleFactor(0.62)

            Text("\(Self.displayMetersRounded(snapshot.legs[manualDisplayedIndex].distanceMeters)) m")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Back") {
                    manualStepIndex = max(0, manualStepIndex - 1)
                }
                .disabled(manualStepIndex == 0)

                Button("Next") {
                    manualStepIndex = min(snapshot.legs.count - 1, manualStepIndex + 1)
                }
                .disabled(manualStepIndex >= snapshot.legs.count - 1)
            }
        }
    }

    private static func displayMinutes(fromSeconds seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return Int(seconds / 60)
    }

    private static func displayMetersRounded(_ meters: Double) -> Int {
        guard meters.isFinite, meters >= 0 else { return 0 }
        return Int(meters.rounded())
    }
}

#Preview {
    RandomWalkerWatchRootView()
}
