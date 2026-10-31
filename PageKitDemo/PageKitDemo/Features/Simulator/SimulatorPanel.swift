import SwiftUI

/// The control room: switch between live and simulated news, then make the simulated
/// network slow, flaky or absent and watch the feeds cope.
struct SimulatorPanel: View {
    let environment: AppEnvironment
    @Bindable var model: SimulatorViewModel
    @Environment(\.dismiss) private var dismiss

    private var isMock: Bool { environment.mode == .mock }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Source") { modePicker }
                    section("Network", note: isMock ? nil : "These controls only affect mock data. Switch to Mock to use them.") {
                        networkControls
                    }
                    section("Caches") { cacheControls }
                }
                .padding(16)
            }
        }
        .background(Palette.paper)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Simulator")
                .font(Typography.stateTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .font(Typography.kicker)
                .accessibilityIdentifier("simulator.close")
        }
        .foregroundStyle(Palette.onSignal)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Palette.signal)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: modeBinding) {
                Text("Live").tag(AppEnvironment.Mode.live)
                Text("Mock").tag(AppEnvironment.Mode.mock)
            }
            .pickerStyle(.segmented)
            .disabled(environment.isSwitching)
            .accessibilityIdentifier("simulator.mode")
            if environment.isSwitching {
                Text("Clearing caches and rebuilding the feeds…").font(Typography.notice)
            }
        }
    }

    private var networkControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            slider("Latency", value: $model.latency, range: 0...3, label: model.latency == 0 ? "None" : "up to \(model.latency.formatted(.number.precision(.fractionLength(1)))) s", id: "simulator.latency")
            slider("Failure rate", value: $model.failureRate, range: 0...1, label: model.failureRate.formatted(.percent.precision(.fractionLength(0))), id: "simulator.failure")
            Toggle("Offline", isOn: $model.isOffline)
                .font(Typography.headline)
                .tint(Palette.signal)
                .accessibilityIdentifier("simulator.offline")
            actionButton("Chaos preset", id: "simulator.chaos") { model.applyChaos() }
        }
        .disabled(!isMock)
        .opacity(isMock ? 1 : 0.45)
    }

    private var cacheControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionButton("Clear caches", id: "simulator.clear") {
                Task { await model.clearCaches() }
            }
            actionButton("Simulate memory warning", id: "simulator.memory") { model.simulateMemoryWarning() }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Typography.kicker)
                .foregroundStyle(Palette.signalText)
            Rule(weight: 1.5, color: Palette.ink)
            content()
            if let note {
                Text(note).font(Typography.notice)
            }
        }
        .foregroundStyle(Palette.ink)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Typography.headline)
                Spacer()
                Text(label).font(Typography.meta.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
            }
            Slider(value: value, in: range)
                .tint(Palette.signal)
                .accessibilityLabel(title)
                .accessibilityValue(label)
                .accessibilityIdentifier(id)
        }
    }

    private func actionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.kicker)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Palette.ink)
                .overlay(Rectangle().stroke(Palette.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var modeBinding: Binding<AppEnvironment.Mode> {
        Binding(
            get: { environment.mode },
            set: { newMode in
                Task { await environment.switchMode(to: newMode) }
            }
        )
    }
}
