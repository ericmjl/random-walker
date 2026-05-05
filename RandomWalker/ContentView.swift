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
    /// North-up overview of the full planned route while navigating (Apple Maps–style route preview).
    @State private var navigationShowsRouteOverview = false

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
            .onChange(of: session.isNavigating) { _, navigating in
                if !navigating { navigationShowsRouteOverview = false }
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

    /// During **Start walk**: map-first full-bleed layout with a top instruction card, bottom trip sheet, and floating controls (Apple Maps–inspired).
    @ViewBuilder
    private var turnByTurnWithMapView: some View {
        GeometryReader { geo in
            let hasSteps = session.navigationStepCount > 0
            ZStack(alignment: .bottom) {
                WalkMapCard(
                    coordinates: session.refinedWalk?.coordinates ?? [],
                    userCoordinate: locationService.lastLocation?.coordinate,
                    isNavigating: true,
                    userCourse: userCourseFromLocation,
                    maneuverCoordinate: session.maneuverCoordinateForNavigation(),
                    navigationStepIndex: session.navigationDisplayedStepIndex,
                    isBrowsingStepsAwayFromLive: session.isBrowsingAwayFromLiveNavigationStep,
                    showRouteOverview: navigationShowsRouteOverview
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if hasSteps {
                    VStack(spacing: 0) {
                        navigationTopInstructionStack(maxWidth: geo.size.width)
                        Spacer(minLength: 0)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom) {
                            Spacer(minLength: 0)
                            navigationFloatingControlStack
                        }
                        navigationBottomTripSheet
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    /// Top card + **Follow live** when paging away from the GPS step.
    @ViewBuilder
    private func navigationTopInstructionStack(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationGuidancePagerCard(maxWidth: maxWidth)
            if session.isBrowsingAwayFromLiveNavigationStep {
                Button("Follow live") {
                    session.clearNavigationBrowse()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    /// Swipe between maneuvers inside a high-contrast banner (page dots hidden; edge chevrons hint paging).
    @ViewBuilder
    private func navigationGuidancePagerCard(maxWidth: CGFloat) -> some View {
        let cardHeight: CGFloat = min(200, max(132, maxWidth * 0.34))
        ZStack {
            if session.navigationStepCount > 1 {
                TabView(selection: navigationStepPageSelection) {
                    ForEach(0 ..< session.navigationStepCount, id: \.self) { stepIdx in
                        navigationGuidancePage(stepIndex: stepIdx)
                            .tag(stepIdx)
                            .padding(.horizontal, 18)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityHint("Swipe left or right to view other steps on this route.")
            } else if session.navigationStepCount == 1 {
                TabView(selection: navigationStepPageSelection) {
                    navigationGuidancePage(stepIndex: 0)
                        .tag(0)
                        .padding(.horizontal, 18)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            HStack(spacing: 0) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .opacity(navigationPagerLeadingChevronOpacity)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .opacity(navigationPagerTrailingChevronOpacity)
                    .padding(.trailing, 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.82))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    private var navigationFloatingControlStack: some View {
        VStack(spacing: 12) {
            navigationFloatingIconButton(
                systemImage: navigationShowsRouteOverview ? "location.north.line.fill" : "map",
                accessibilityLabel: navigationShowsRouteOverview ? "Follow location" : "Route overview"
            ) {
                navigationShowsRouteOverview.toggle()
            }
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .opacity(0.42)
                .accessibilityLabel("Voice guidance not available")
        }
    }

    private func navigationFloatingIconButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var navigationBottomTripSheet: some View {
        let pace = max(0.5, walkingPace.effectiveWalkingSpeedMetersPerSecond)
        let loc = locationService.lastLocation
        let remainingMeters = loc.flatMap { session.navigationRemainingDistanceApprox(from: $0) }
        let remainingSeconds = loc.flatMap { session.navigationRemainingDurationApprox(from: $0, walkingSpeedMetersPerSecond: pace) }
        let arrival: Date? = remainingSeconds.map { Date().addingTimeInterval($0) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arrive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(arrival.map { PlanWalkView.formatShortTime($0) } ?? "—")
                        .font(.title3.weight(.bold))
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(remainingSeconds.map { PlanWalkView.formatMinutesRounded($0) } ?? "—")
                        .font(.title3.weight(.bold))
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(remainingMeters.map { PlanWalkView.formatDistanceMeters($0) } ?? "—")
                        .font(.title3.weight(.bold))
                }
            }
            Button {
                showStopGuidanceConfirmation = true
            } label: {
                Label("End walk", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.92))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThickMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    @ViewBuilder
    private func navigationGuidancePage(stepIndex: Int) -> some View {
        let instruction = session.navigationInstructionTextForStep(at: stepIndex) ?? "Continue"
        let symbol = NavigationManeuverGlyph.systemImage(for: instruction)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let loc = locationService.lastLocation,
                   let meters = session.distanceToManeuver(forStepIndex: stepIndex, from: loc) {
                    Text("In \(PlanWalkView.formatDistanceMeters(meters))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            Text(instruction)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.88)
                .fixedSize(horizontal: false, vertical: true)
            if let then = session.navigationThenTextForStep(after: stepIndex) {
                Text(then)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Step \(stepIndex + 1) of \(session.navigationStepCount). Swipe horizontally to review other steps.")
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

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func formatShortTime(_ date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    private static func formatMinutesRounded(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 1 { return "< 1 min" }
        return "\(m) min"
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
    /// North-up full-route framing (user toggle) while navigating.
    var showRouteOverview: Bool = false

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
            .onChange(of: showRouteOverview) { _, _ in
                if isNavigating { applyNavigationCamera() }
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
        if showRouteOverview {
            applyNavigationRouteOverview()
        } else if isBrowsingStepsAwayFromLive {
            applyBrowsingOverviewCamera()
        } else {
            applyNavigationFollowCamera()
        }
    }

    /// Entire planned loop, north up (Apple Maps route-preview style).
    private func applyNavigationRouteOverview() {
        guard coordinates.count >= 2 else {
            navigationCameraHeading = 0
            if let userCoordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(center: userCoordinate, latitudinalMeters: 900, longitudinalMeters: 900)
                )
            }
            return
        }
        let mapPoints = coordinates.map(MKMapPoint.init)
        let rect = mapPoints.reduce(MKMapRect.null) { partial, point in
            partial.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        let region = MKCoordinateRegion(rect)
        navigationCameraHeading = 0
        cameraPosition = .region(region)
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

/// SF Symbol for MapKit-style walking instructions (English heuristics).
private enum NavigationManeuverGlyph {
    static func systemImage(for instruction: String) -> String {
        let s = instruction.lowercased()
        if s.contains("u-turn") || s.contains("uturn") || s.contains("make a u") {
            return "arrow.uturn.backward.circle.fill"
        }
        if s.contains("slight right") {
            return "arrow.up.right"
        }
        if s.contains("slight left") {
            return "arrow.up.left"
        }
        if s.contains("sharp right") || s.contains("hard right") {
            return "arrow.turn.up.right"
        }
        if s.contains("sharp left") || s.contains("hard left") {
            return "arrow.turn.up.left"
        }
        if s.contains("turn right") || s.contains("bear right") || s.contains("right onto") {
            return "arrow.turn.up.right"
        }
        if s.contains("turn left") || s.contains("bear left") || s.contains("left onto") {
            return "arrow.turn.up.left"
        }
        if s.contains("merge") {
            return "arrow.merge"
        }
        if s.contains("roundabout") || s.contains("rotary") {
            return "arrow.trianglehead.merge"
        }
        if s.contains("destination") || s.contains("arrive") || s.contains("arriving") {
            return "flag.checkered"
        }
        if s.contains("continue") || s.contains("head ") || s.hasPrefix("walk ") {
            return "arrow.up"
        }
        return "arrow.up.circle.fill"
    }
}
