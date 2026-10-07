import SwiftUI

struct PerformanceSection: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject private var metricsModel: PerformanceModel
    init(model: WorkspaceModel) {
        self.model = model
        self.metricsModel = model.performance
    }
    var body: some View {
        Section {
            AdaptiveValueRow("App CPU", value: metricsModel.process.cpuPercent.map {
                $0.formatted(.number.precision(.fractionLength(1))) + "%"
            } ?? "—").accessibilityIdentifier("cpuUsage")
            AdaptiveValueRow("App RAM", value: metricsModel.process.memoryBytes.map {
                $0.formatted(.byteCount(style: .memory))
            } ?? "—").accessibilityIdentifier("ramUsage")
            if let headroom = metricsModel.process.headroomBytes {
                AdaptiveValueRow("App memory headroom", value: headroom.formatted(.byteCount(style: .memory)))
            }
            if let metrics = metricsModel.transfer {
                if let fraction = metrics.fraction {
                    ProgressView(value: fraction) {
                        Text("Progress")
                    } currentValueLabel: {
                        Text(fraction.formatted(.percent.precision(.fractionLength(1))))
                    }.accessibilityIdentifier("operationProgress")
                } else if model.isBusy {
                    ProgressView(model.status).accessibilityIdentifier("operationProgress")
                }
                AdaptiveValueRow(metrics.finished ? "Average speed" : "Speed", value: speed(metrics.bytesPerSecond))
                    .accessibilityIdentifier("operationSpeed")
                AdaptiveValueRow("Processed", value: metrics.bytes.formatted(.byteCount(style: .file))
                    + (metrics.total > 0 ? " / " + metrics.total.formatted(.byteCount(style: .file)) : ""))
                    .accessibilityIdentifier("processedBytes")
                AdaptiveValueRow("Elapsed", value: metrics.seconds.formatted(.number.precision(.fractionLength(1))) + " s")
            } else if model.isBusy { ProgressView(model.status) }
        } header: {
            Text("Performance")
        } footer: {
            Text("CPU: 100% is one core. RAM is this app's footprint, not device-wide usage. Speed counts uncompressed input when creating and output when extracting. Verification and solid decoding may pause progress.")
        }
        .monospacedDigit()
    }
    private func speed(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, value))), countStyle: .file) + "/s"
    }
}

/// Keep active work visible even when a long source list pushes the Form's
/// detailed metrics below the viewport. System safe areas own the placement.
struct LiveOperationView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject private var metricsModel: PerformanceModel
    init(model: WorkspaceModel) { self.model = model; metricsModel = model.performance }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.status).accessibilityIdentifier("liveOperationStatus")
                Spacer()
                if let fraction = metricsModel.transfer?.fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(1))))
                        .monospacedDigit().accessibilityIdentifier("liveOperationPercent")
                }
            }.font(.caption)
            if let metrics = metricsModel.transfer {
                if let fraction = metrics.fraction {
                    ProgressView(value: fraction).accessibilityIdentifier("liveOperationProgress")
                } else { ProgressView().accessibilityIdentifier("liveOperationProgress") }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        transferText(metrics)
                        Spacer()
                        processedText(metrics)
                    }
                    VStack(alignment: .leading) { transferText(metrics); processedText(metrics) }
                }.font(.caption).monospacedDigit()
            } else { ProgressView() }
            ViewThatFits(in: .horizontal) {
                HStack { cpuText; Spacer(); ramText }
                VStack(alignment: .leading) { cpuText; ramText }
            }.font(.caption).monospacedDigit()
        }
        .padding(.horizontal).padding(.vertical, 8).frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
    private var cpuText: some View {
        Text(String(localized: "App CPU") + ": " + (metricsModel.process.cpuPercent.map {
            $0.formatted(.number.precision(.fractionLength(1))) + "%"
        } ?? "—")).accessibilityIdentifier("liveCPUUsage")
    }
    private var ramText: some View {
        Text(String(localized: "App RAM") + ": " + (metricsModel.process.memoryBytes.map {
            $0.formatted(.byteCount(style: .memory))
        } ?? "—")).accessibilityIdentifier("liveRAMUsage")
    }
    private func transferText(_ metrics: OperationMetrics) -> some View {
        Text(String(localized: "Speed") + ": " + ByteCountFormatter.string(
            fromByteCount: Int64(min(Double(Int64.max / 2), max(0, metrics.bytesPerSecond))), countStyle: .file) + "/s")
            .accessibilityIdentifier("liveOperationSpeed")
    }
    private func processedText(_ metrics: OperationMetrics) -> some View {
        Text(String(localized: "Processed") + ": " + metrics.bytes.formatted(.byteCount(style: .file))
             + (metrics.total > 0 ? " / " + metrics.total.formatted(.byteCount(style: .file)) : ""))
            .accessibilityIdentifier("liveProcessedBytes")
    }
}
