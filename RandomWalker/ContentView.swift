import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import UIKit
import RandomWalkerCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationService = LocationService()
    @StateObject private var connectivity = PhoneConnectivityManager()
    @State private var session = WalkSessionViewModel()

    var body: some View {
        TabView {
            PlanWalkView(
                locationService: locationService,
                connectivity: connectivity,
                session: session
            )
            .tabItem {
                Label("Plan", systemImage: "figure.walk.motion")
            }

            WalkHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .task {
            locationService.requestWhenInUse()
            locationService.startUpdates()
        }
        .onChange(of: locationService.authorizationStatus) { _, newStatus in
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                locationService.startUpdates()
            }
        }
    }
}

struct PlanWalkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @ObservedObject var locationService: LocationService
    @ObservedObject var connectivity: PhoneConnectivityManager
    @Bindable var session: WalkSessionViewModel
    @State private var isResolvingLocation = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                locationPermissionCallout

                WalkMapCard(
                    coordinates: session.refinedWalk?.coordinates ?? [],
                    userCoordinate: locationService.lastLocation?.coordinate,
                    isNavigating: session.isNavigating,
                    userCourse: userCourseFromLocation,
                    maneuverCoordinate: session.maneuverCoordinateForNavigation(),
                    navigationStepIndex: session.navigationStepIndex
                )
                .frame(height: session.isNavigating ? 380 : 320)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if session.isNavigating {
                    navigationGuidanceCard
                }

                statusSection

                if session.refinedWalk != nil {
                    if session.isNavigating {
                        Button(role: .cancel) {
                            session.stopNavigation()
                        } label: {
                            Label("Stop guidance", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            session.startNavigation(seedLocation: locationService.lastLocation)
                        } label: {
                            Label("Start", systemImage: "location.north.line.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button(action: startPlanning) {
                    Label("Hour-long random loop", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isPlanning || isResolvingLocation || !locationService.canStartPlanning)

                Button(role: .destructive) {
                    session.clearActiveWalk(connectivity: connectivity)
                } label: {
                    Label("Clear map", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Random Walker")
            .onChange(of: locationService.lastLocation) { _, newValue in
                guard let newValue, session.isNavigating else { return }
                session.ingestNavigationLocation(newValue, modelContext: modelContext)
            }
            .alert(
                "Walk complete",
                isPresented: Binding(
                    get: { session.navigationCompletionNotice != nil },
                    set: { _ in }
                )
            ) {
                Button("OK") {
                    session.acknowledgeNavigationCompletion()
                }
            } message: {
                Text(session.navigationCompletionNotice ?? "")
            }
        }
    }

    private var userCourseFromLocation: CLLocationDirection? {
        guard let course = locationService.lastLocation?.course, course >= 0 else { return nil }
        return course
    }

    @ViewBuilder
    private var navigationGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let primary = session.navigationInstructionText() {
                Text(primary)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loc = locationService.lastLocation,
               let meters = session.distanceToNavigationManeuver(from: loc) {
                Text("In \(PlanWalkView.formatDistanceMeters(meters))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let then = session.navigationThenText() {
                Text(then)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.navigationStepCount > 0 {
                Text("Step \(session.navigationStepIndex + 1) of \(session.navigationStepCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func formatDistanceMeters(_ m: CLLocationDistance) -> String {
        if m >= 1_000 {
            return String(format: "%.1f km", m / 1_000)
        }
        return "\(Int(round(m))) m"
    }

    @ViewBuilder
    private var locationPermissionCallout: some View {
        switch locationService.authorizationStatus {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                Text("Use your current location")
                    .font(.headline)
                Text("Random Walker needs access so each loop starts and ends where you are standing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Allow location access") {
                    locationService.requestWhenInUse()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 10) {
                Text("Location is off")
                    .font(.headline)
                Text("Enable location in Settings so the app can use your position as the walk start.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        default:
            EmptyView()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = session.planningError {
                Text(error)
                    .foregroundStyle(.red)
            } else if let summary = session.refinementSummary {
                Text(summary)
                    .foregroundStyle(.secondary)
            } else {
                Text(instructions)
                    .foregroundStyle(.secondary)
            }

            if session.isPlanning {
                ProgressView("Asking Maps for a walking loop…")
            }

            if isResolvingLocation {
                ProgressView("Using your current location…")
            }

            if let walk = session.refinedWalk {
                Text(
                    """
                    About \(Int(walk.expectedTravelTime / 60)) minutes • \
                    \(Int(walk.distanceMeters)) meters • Watch updated
                    """
                )
                .font(.headline)
            }
        }
    }

    private var instructions: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Tap once. Random Walker picks the turns so you don't have to."
        case .denied, .restricted:
            return "Location access is off. Enable it in Settings to build loops from your position."
        default:
            return "Allow location access so every loop starts and ends where you stand."
        }
    }

    private func startPlanning() {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestWhenInUse()
            return
        }

        Task {
            isResolvingLocation = true
            defer { isResolvingLocation = false }

            guard let coordinate = await locationService.coordinateForWalkStart() else { return }

            let waypoint = GeodesicWaypoint(coordinate)
            await session.planHourLoop(
                around: waypoint,
                connectivity: connectivity
            )
        }
    }
}

private struct WalkMapCard: View {
    let coordinates: [CLLocationCoordinate2D]
    let userCoordinate: CLLocationCoordinate2D?
    var isNavigating: Bool = false
    var userCourse: CLLocationDirection?
    var maneuverCoordinate: CLLocationCoordinate2D?
    var navigationStepIndex: Int = 0

    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Avoids resetting zoom on every GPS tick; we only auto-frame when the route changes or the user first appears.
    @State private var didAutoFrameUserOnlyMap = false

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            if let userCoordinate {
                Marker("You", coordinate: userCoordinate)
                    .tint(.green)
            }

            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 6)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        /// Keep `cameraPosition` in sync after user pinch / pan / rotate / tilt (plan mode only).
        /// During navigation we drive the camera programmatically; committing `onMapCameraChange` here
        /// can fight MapKit and **freeze the main thread** (watchdog → SIGTERM).
        .onMapCameraChange(frequency: .onEnd) { context in
            guard !isNavigating else { return }
            cameraPosition = .camera(context.camera)
        }
        .onChange(of: coordinates.count) { _, _ in
            if coordinates.count < 2 {
                didAutoFrameUserOnlyMap = false
            }
            fitCameraToRouteOrUser()
        }
        .onChange(of: userCoordinate == nil) { wasNil, isNilNow in
            guard coordinates.count < 2, !isNavigating else { return }
            let userJustAppeared = wasNil && !isNilNow
            let needsInitialFrame = !didAutoFrameUserOnlyMap && !isNilNow
            guard userJustAppeared || needsInitialFrame else { return }
            fitCameraToRouteOrUser()
        }
        .onChange(of: navigationStepIndex) { _, _ in
            if isNavigating {
                applyNavigationFollowCamera()
            }
        }
        .onChange(of: isNavigating) { _, active in
            if active {
                applyNavigationFollowCamera()
            } else {
                fitCameraToRouteOrUser()
            }
        }
        .onAppear {
            fitCameraToRouteOrUser()
        }
    }

    private func fitCameraToRouteOrUser() {
        guard !isNavigating else { return }
        guard !coordinates.isEmpty else {
            if let userCoordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 900, longitudinalMeters: 900)
                )
                didAutoFrameUserOnlyMap = true
            }
            return
        }

        let mapPoints = coordinates.map(MKMapPoint.init)
        let rect = mapPoints.reduce(MKMapRect.null) { partial, point in
            partial.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        let region = MKCoordinateRegion(rect)
        cameraPosition = .region(region)
    }

    /// Apple Maps–style chase camera: slight pitch, heading from GPS course or bearing toward the maneuver.
    private func applyNavigationFollowCamera() {
        guard isNavigating, let userCoordinate else { return }
        let heading: CLLocationDirection
        if let userCourse, userCourse >= 0 {
            heading = userCourse
        } else if let maneuverCoordinate {
            heading = WalkRouteNavigator.bearing(from: userCoordinate, to: maneuverCoordinate)
        } else {
            heading = 0
        }
        let camera = MapCamera(
            centerCoordinate: userCoordinate,
            distance: 240,
            heading: heading,
            pitch: 35
        )
        cameraPosition = .camera(camera)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: WalkRecord.self, inMemory: true)
}
