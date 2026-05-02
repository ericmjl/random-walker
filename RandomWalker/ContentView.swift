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
    @StateObject private var walkingPace = WalkingPaceService()
    @State private var session = WalkSessionViewModel()

    var body: some View {
        TabView {
            PlanWalkView(
                locationService: locationService,
                connectivity: connectivity,
                walkingPace: walkingPace,
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
        .onAppear {
            session.onWalkSavedObservedPace = { distanceMeters, durationSeconds in
                walkingPace.ingestObservedWalk(distanceMeters: distanceMeters, durationSeconds: durationSeconds)
            }
        }
        .task {
            walkingPace.bootstrapFromHistoryIfNeeded(modelContext: modelContext)
            await walkingPace.requestWalkingSpeedReadAccessIfNeeded()
            await walkingPace.refreshAuthorizedHealthKitData()
            #if targetEnvironment(simulator)
            await walkingPace.seedSimulatorWalkingSpeedFixtures()
            #endif
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
    @ObservedObject var walkingPace: WalkingPaceService
    @Bindable var session: WalkSessionViewModel
    @State private var isResolvingLocation = false
    @State private var showStopGuidanceConfirmation = false
    @State private var showNewRouteSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if session.isNavigating {
                    turnByTurnWithMapView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                } else {
                    planAndMapScrollContent
                }
            }
            .navigationTitle(session.isNavigating ? "" : "Random Walker")
            .navigationBarTitleDisplayMode(session.isNavigating ? .inline : .large)
            .toolbar {
                if session.isNavigating {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End walk", systemImage: "xmark.circle") {
                            showStopGuidanceConfirmation = true
                        }
                        .accessibilityLabel("End walk")
                    }
                } else if session.refinedWalk != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear map", systemImage: "xmark.circle") {
                            session.clearActiveWalk(connectivity: connectivity)
                        }
                    }
                }
            }
            .toolbar(session.isNavigating ? .hidden : .automatic, for: .tabBar)
            .confirmationDialog(
                "Stop guidance?",
                isPresented: $showStopGuidanceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save to history") {
                    Task {
                        await session.stopAndSaveToHistory(
                            modelContext: modelContext,
                            connectivity: connectivity
                        )
                    }
                }
                Button("Discard", role: .destructive) {
                    session.discardNavigationWithoutSaving(connectivity: connectivity)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save your GPS path so far, discard it, or keep navigating.")
            }
            .sheet(isPresented: $showNewRouteSheet) {
                NewRoutePlanningSheet(
                    lengthGoal: $session.planningLengthGoal,
                    walkingSpeedMetersPerSecond: walkingPace.effectiveWalkingSpeedMetersPerSecond
                ) {
                    Task {
                        await startPlanningAfterSheet()
                    }
                }
            }
            .onChange(of: locationService.lastLocation) { _, newValue in
                guard let newValue, session.isNavigating else { return }
                session.ingestNavigationLocation(
                    newValue,
                    modelContext: modelContext,
                    connectivity: connectivity
                )
            }
            .onAppear {
                connectivity.onWatchRecordedTrack = { track in
                    session.ingestWatchRecording(track)
                }
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

    /// Planning / pre-start UI: map, status, and route actions.
    @ViewBuilder
    private var planAndMapScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                locationPermissionCallout

                WalkMapCard(
                    coordinates: session.refinedWalk?.coordinates ?? [],
                    userCoordinate: locationService.lastLocation?.coordinate,
                    isNavigating: false,
                    userCourse: userCourseFromLocation,
                    maneuverCoordinate: session.maneuverCoordinateForNavigation(),
                    navigationStepIndex: session.navigationStepIndex,
                    isBrowsingStepsAwayFromLive: false
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                statusSection

                if session.refinedWalk != nil {
                    routeReadyActions
                } else {
                    planRouteEntryButton
                }
            }
            .padding()
        }
    }

    /// Swipe selection for paging maneuvers vs live GPS step (see ``WalkSessionViewModel/navigationBrowseStepIndex``).
    private var navigationStepPageSelection: Binding<Int> {
        Binding(
            get: { session.navigationDisplayedStepIndex },
            set: { newValue in
                let live = session.navigationStepIndex
                let maxIdx = max(0, session.navigationStepCount - 1)
                let clamped = min(max(0, newValue), maxIdx)
                if clamped == live {
                    session.clearNavigationBrowse()
                } else {
                    session.navigationBrowseStepIndex = clamped
                }
            }
        )
    }

    /// Subtle edge chevrons: brighter when another step exists in that direction.
    private var navigationPagerLeadingChevronOpacity: Double {
        guard session.navigationStepCount > 1 else { return 0 }
        return session.navigationDisplayedStepIndex > 0 ? 0.42 : 0.12
    }

    private var navigationPagerTrailingChevronOpacity: Double {
        guard session.navigationStepCount > 1 else { return 0 }
        let lastIndex = session.navigationStepCount - 1
        return session.navigationDisplayedStepIndex < lastIndex ? 0.42 : 0.12
    }

    /// During **Start walk**: turn-by-turn text plus live chase-map, heading arrow, and next-turn marker.
    @ViewBuilder
    private var turnByTurnWithMapView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.navigationStepCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    if session.navigationStepCount > 1 {
                        ZStack {
                            TabView(selection: navigationStepPageSelection) {
                                ForEach(0 ..< session.navigationStepCount, id: \.self) { stepIdx in
                                    navigationGuidancePage(stepIndex: stepIdx)
                                        .tag(stepIdx)
                                        .padding(.horizontal, 22)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .automatic))
                            .accessibilityHint("Swipe left or right to view other steps on this route.")

                            HStack(spacing: 0) {
                                Image(systemName: "chevron.compact.left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .opacity(navigationPagerLeadingChevronOpacity)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.compact.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .opacity(navigationPagerTrailingChevronOpacity)
                            }
                            .padding(.horizontal, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                        .frame(minHeight: 172)
                    } else if session.navigationStepCount == 1 {
                        TabView(selection: navigationStepPageSelection) {
                            navigationGuidancePage(stepIndex: 0)
                                .tag(0)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(minHeight: 172)
                    }

                    if session.isBrowsingAwayFromLiveNavigationStep {
                        Button("Follow live") {
                            session.clearNavigationBrowse()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            WalkMapCard(
                coordinates: session.refinedWalk?.coordinates ?? [],
                userCoordinate: locationService.lastLocation?.coordinate,
                isNavigating: true,
                userCourse: userCourseFromLocation,
                maneuverCoordinate: session.maneuverCoordinateForNavigation(),
                navigationStepIndex: session.navigationDisplayedStepIndex,
                isBrowsingStepsAwayFromLive: session.isBrowsingAwayFromLiveNavigationStep
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func navigationGuidancePage(stepIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let primary = session.navigationInstructionTextForStep(at: stepIndex) {
                Text(primary)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loc = locationService.lastLocation,
               let meters = session.distanceToManeuver(forStepIndex: stepIndex, from: loc) {
                Text("In \(PlanWalkView.formatDistanceMeters(meters))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let then = session.navigationThenTextForStep(after: stepIndex) {
                Text(then)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Step \(stepIndex + 1) of \(session.navigationStepCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var routeReadyActions: some View {
        VStack(spacing: 14) {
            Button {
                session.startNavigation(
                    seedLocation: locationService.lastLocation,
                    connectivity: connectivity
                )
            } label: {
                Label("Start walk", systemImage: "figure.walk")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                presentNewRouteSheetIfLocationReady()
            } label: {
                VStack(spacing: 6) {
                    Label("New route", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text("Set time or distance, then rebuild the loop")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(session.isPlanning || isResolvingLocation || !locationService.canStartPlanning)
        }
    }

    @ViewBuilder
    private var planRouteEntryButton: some View {
        Button {
            presentNewRouteSheetIfLocationReady()
        } label: {
            VStack(spacing: 6) {
                Label("Plan a walking route", systemImage: "map")
                    .font(.headline)
                Text("Choose how long or how far, then build a random loop from here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(session.isPlanning || isResolvingLocation || !locationService.canStartPlanning)
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
                let paceMetersPerSecond = max(0.5, walkingPace.effectiveWalkingSpeedMetersPerSecond)
                let paceMinutes = max(1, Int(round(walk.distanceMeters / paceMetersPerSecond / 60)))
                Text(
                    """
                    About \(paceMinutes) min at your pace • \
                    \(Int(walk.distanceMeters)) m • Apple Watch route when paired
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

    private func presentNewRouteSheetIfLocationReady() {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestWhenInUse()
            return
        }
        guard locationService.canStartPlanning else { return }
        showNewRouteSheet = true
    }

    private func startPlanningAfterSheet() async {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestWhenInUse()
            return
        }

        isResolvingLocation = true
        defer { isResolvingLocation = false }

        guard let coordinate = await locationService.coordinateForWalkStart() else { return }

        let waypoint = GeodesicWaypoint(coordinate)
        await session.planLoop(
            around: waypoint,
            connectivity: connectivity,
            walkingSpeedMetersPerSecond: walkingPace.effectiveWalkingSpeedMetersPerSecond
        )
    }

}

private struct WalkMapCard: View {
    let coordinates: [CLLocationCoordinate2D]
    let userCoordinate: CLLocationCoordinate2D?
    var isNavigating: Bool = false
    var userCourse: CLLocationDirection?
    var maneuverCoordinate: CLLocationCoordinate2D?
    var navigationStepIndex: Int = 0
    /// When true, map frames user + **displayed** maneuver (browsing). When false during navigation, chase camera stays on the user (live step).
    var isBrowsingStepsAwayFromLive: Bool = false

    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Avoids resetting zoom on every GPS tick; we only auto-frame when the route changes or the user first appears.
    @State private var didAutoFrameUserOnlyMap = false
    /// Matches the chase camera heading so the user arrow aligns with map north / forward on screen.
    @State private var navigationCameraHeading: CLLocationDirection = 0

    var body: some View {
        withLocationAndManeuverHandlers(withNavigationCameraHandlers(mapWithPlanModeHandlers))
    }

    /// Breaks up modifier chains so the type checker can finish within the time limit.
    @ViewBuilder
    private func withNavigationCameraHandlers<V: View>(_ base: V) -> some View {
        base
            .onChange(of: navigationStepIndex) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onChange(of: isBrowsingStepsAwayFromLive) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onChange(of: isNavigating) { _, active in
                if active {
                    applyNavigationCamera()
                } else {
                    fitCameraToRouteOrUser()
                }
            }
    }

    @ViewBuilder
    private func withLocationAndManeuverHandlers<V: View>(_ base: V) -> some View {
        base
            .onChange(of: userCoordinate?.latitude ?? 0) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onChange(of: userCoordinate?.longitude ?? 0) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onChange(of: maneuverCoordinate?.latitude ?? 0) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onChange(of: maneuverCoordinate?.longitude ?? 0) { _, _ in
                if isNavigating { applyNavigationCamera() }
            }
            .onAppear {
                fitCameraToRouteOrUser()
            }
    }

    private var mapWithPlanModeHandlers: some View {
        mapContent
            .mapStyle(.standard(elevation: .realistic))
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
    }

    private var mapContent: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            if let userCoordinate {
                if isNavigating {
                    Annotation("", coordinate: userCoordinate) {
                        navigationUserPuck
                    }
                } else {
                    Marker("You", coordinate: userCoordinate)
                        .tint(.green)
                }
            }

            if isNavigating, let maneuverCoordinate {
                Marker("Turn", coordinate: maneuverCoordinate)
                    .tint(.orange)
            }

            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 6)
            }
        }
    }

    /// Heading to use for the forward arrow: GPS course when valid, otherwise bearing toward the upcoming maneuver.
    private var forwardHeadingNorthClockwise: CLLocationDirection {
        guard let userCoordinate else { return 0 }
        if let userCourse, userCourse >= 0 {
            return userCourse
        }
        if let maneuverCoordinate {
            return WalkRouteNavigator.bearing(from: userCoordinate, to: maneuverCoordinate)
        }
        return 0
    }

    private var navigationUserPuck: some View {
        let forwardRot = Self.normalizeAngleDegrees(forwardHeadingNorthClockwise - navigationCameraHeading)
        let showTurnArrow: Double? = {
            guard let userCoordinate, let maneuverCoordinate else { return nil }
            let toTurn = WalkRouteNavigator.bearing(from: userCoordinate, to: maneuverCoordinate)
            let delta = abs(Self.normalizeAngleDegrees(toTurn - forwardHeadingNorthClockwise))
            return delta > 12 ? toTurn : nil
        }()
        return ZStack {
            Circle()
                .fill(.green.opacity(0.95))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: 2)
                }
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -15)
                .rotationEffect(.degrees(forwardRot))
                .accessibilityLabel("Your direction of travel")
            if let toTurn = showTurnArrow {
                let turnRot = Self.normalizeAngleDegrees(toTurn - navigationCameraHeading)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .offset(y: -30)
                    .rotationEffect(.degrees(turnRot))
                    .accessibilityLabel("Toward next turn")
            }
        }
    }

    private static func normalizeAngleDegrees(_ degrees: Double) -> Double {
        var a = degrees.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
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

    private func applyNavigationCamera() {
        guard isNavigating else { return }
        if isBrowsingStepsAwayFromLive {
            applyBrowsingOverviewCamera()
        } else {
            applyNavigationFollowCamera()
        }
    }

    /// North-up region showing both the user and the maneuver for the **browsed** step (so the map matches the card).
    private func applyBrowsingOverviewCamera() {
        guard let userCoordinate, let maneuverCoordinate else {
            applyNavigationFollowCamera()
            return
        }
        let locU = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let locM = CLLocation(latitude: maneuverCoordinate.latitude, longitude: maneuverCoordinate.longitude)
        let separation = locU.distance(from: locM)
        let center = CLLocationCoordinate2D(
            latitude: (userCoordinate.latitude + maneuverCoordinate.latitude) / 2,
            longitude: (userCoordinate.longitude + maneuverCoordinate.longitude) / 2
        )
        let span = max(separation * 1.85, 260)
        let region = MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
        navigationCameraHeading = 0
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
        navigationCameraHeading = heading
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
