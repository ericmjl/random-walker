import SwiftUI
import SwiftData
import MapKit
import RandomWalkerCore

struct WalkHistoryView: View {
    @Query(sort: \WalkRecord.createdAt, order: .reverse) private var walks: [WalkRecord]

    var body: some View {
        NavigationStack {
            Group {
                if walks.isEmpty {
                    ContentUnavailableView(
                        "No walks yet",
                        systemImage: "figure.walk",
                        description: Text("Plan a loop, tap Start, and finish the guided route to save it here.")
                    )
                } else {
                    List {
                        ForEach(walks, id: \.id) { record in
                            NavigationLink {
                                WalkRecordDetailView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title.isEmpty ? "Walk" : record.title)
                                        .font(.headline)
                                    Text(
                                        "\(Int(record.routedExpectedDurationSeconds / 60)) min • \(Int(record.routedDistanceMeters)) m"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct WalkRecordDetailView: View {
    let record: WalkRecord
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        let coords = record.decodedCoordinates.map(\.coordinate)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("About \(Int(record.routedExpectedDurationSeconds / 60)) minutes")
                    .font(.title2.bold())

                Text("Distance: \(Int(record.routedDistanceMeters)) meters")
                    .foregroundStyle(.secondary)

                Map(position: $cameraPosition) {
                    MapPolyline(coordinates: coords)
                        .stroke(.purple.opacity(0.85), lineWidth: 5)
                    Marker("Start & end", coordinate: record.centerWaypoint.coordinate)
                        .tint(.green)
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear {
                    fit(coords: coords)
                }
            }
            .padding()
        }
        .navigationTitle("Walk detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fit(coords: [CLLocationCoordinate2D]) {
        guard coords.count >= 2 else { return }
        let points = coords.map(MKMapPoint.init)
        let rect = points.reduce(MKMapRect.null) { partial, point in
            partial.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        cameraPosition = .region(MKCoordinateRegion(rect))
    }
}

