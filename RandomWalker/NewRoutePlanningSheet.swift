import RandomWalkerCore
import SwiftUI

/// Sheet for choosing **time** or **distance** before ``WalkSessionViewModel/planLoop(around:connectivity:walkingSpeedMetersPerSecond:)``.
struct NewRoutePlanningSheet: View {
    @Binding var lengthGoal: WalkLengthGoal
    /// Pace used when converting between time and distance in the segmented control (typically ``WalkingPaceService/effectiveWalkingSpeedMetersPerSecond``).
    var walkingSpeedMetersPerSecond: Double
    /// Called after the sheet dismisses with ``lengthGoal`` already updated.
    var onBuild: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var planByTime: Bool = true
    @State private var minutes: Double = 60
    @State private var distanceKilometers: Double = 5

    private static let minutesRange: ClosedRange<Double> = 15 ... 180
    private static let kilometersRange: ClosedRange<Double> = 0.8 ... 12

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Plan by", selection: $planByTime) {
                        Text("Walking time").tag(true)
                        Text("Route distance").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(
                        planByTime
                            ? "Maps will aim for roughly this duration; streets and detours vary the real walk."
                            : "Maps will aim for roughly this path length along the loop."
                    )
                }

                if planByTime {
                    Section("Target duration") {
                        Slider(value: $minutes, in: Self.minutesRange, step: 5) {
                            Text("Minutes")
                        } minimumValueLabel: {
                            Text("15m").font(.caption2)
                        } maximumValueLabel: {
                            Text("3h").font(.caption2)
                        }
                        Text("\(Int(minutes)) minutes")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Target duration \(Int(minutes)) minutes")
                    }
                } else {
                    Section("Target distance") {
                        Slider(value: $distanceKilometers, in: Self.kilometersRange, step: 0.2) {
                            Text("Kilometers")
                        } minimumValueLabel: {
                            Text("0.8").font(.caption2)
                        } maximumValueLabel: {
                            Text("12").font(.caption2)
                        }
                        Text(distanceSummary)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Target distance \(distanceSummary)")
                    }
                }

                Section {
                    Button(action: commitAndBuild) {
                        Label("Build route", systemImage: "map")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Creates a new loop with the time or distance you chose.")
                }
            }
            .navigationTitle("New route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                syncLocalStateFromGoal()
            }
            .onChange(of: planByTime) { _, nowTime in
                if nowTime {
                    let derived =
                        (distanceKilometers * 1_000)
                            / (walkingSpeedMetersPerSecond * 60)
                    minutes = derived.clamped(to: Self.minutesRange)
                } else {
                    let derivedKm =
                        (minutes * 60 * walkingSpeedMetersPerSecond) / 1_000
                    distanceKilometers = derivedKm.clamped(to: Self.kilometersRange)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var distanceSummary: String {
        if distanceKilometers >= 1 {
            return String(format: "%.1f km", distanceKilometers)
        }
        return "\(Int(distanceKilometers * 1_000)) m"
    }

    private func syncLocalStateFromGoal() {
        switch lengthGoal {
        case .duration(let seconds):
            planByTime = true
            minutes = (seconds / 60).clamped(to: Self.minutesRange)
        case .distance(let meters):
            planByTime = false
            distanceKilometers = (meters / 1_000).clamped(to: Self.kilometersRange)
        }
    }

    private func applyGoal() {
        if planByTime {
            lengthGoal = .duration(minutes * 60)
        } else {
            lengthGoal = .distance(meters: distanceKilometers * 1_000)
        }
    }

    private func commitAndBuild() {
        applyGoal()
        dismiss()
        onBuild()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

#Preview {
    NewRoutePlanningSheet(
        lengthGoal: .constant(.duration(3_600)),
        walkingSpeedMetersPerSecond: RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond,
        onBuild: {}
    )
}
