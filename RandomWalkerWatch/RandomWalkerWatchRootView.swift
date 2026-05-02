import SwiftUI
import RandomWalkerCore

struct RandomWalkerWatchRootView: View {
    @StateObject private var coordinator = WatchWalkCoordinator()

    var body: some View {
        NavigationStack {
            if let snapshot = coordinator.snapshot {
                WatchRouteView(snapshot: snapshot)
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
    @State private var index: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(snapshot.expectedDurationSeconds / 60)) min est.")
                    .font(.headline)
                Spacer()
                Text("\(Int(snapshot.totalDistanceMeters)) m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if snapshot.legs.isEmpty {
                Text("No turn cues available—stay on the route shown on your phone.")
                    .font(.footnote)
            } else {
                Text("Step \(index + 1) / \(snapshot.legs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(snapshot.legs[index].title)
                    .font(.body)
                    .minimumScaleFactor(0.7)

                Text("\(Int(snapshot.legs[index].distanceMeters)) m")
                    .font(.caption2)

                HStack {
                    Button("Back") {
                        index = max(0, index - 1)
                    }
                    .disabled(index == 0)

                    Button("Next") {
                        index = min(snapshot.legs.count - 1, index + 1)
                    }
                    .disabled(index >= snapshot.legs.count - 1)
                }
            }
        }
        .navigationTitle("Walk")
        .padding(.vertical, 4)
    }
}

#Preview {
    RandomWalkerWatchRootView()
}
