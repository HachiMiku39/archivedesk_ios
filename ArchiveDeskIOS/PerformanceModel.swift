import Combine

// Sampling invalidates only the small metrics panel, not the archive listing.
@MainActor
final class PerformanceModel: ObservableObject {
    @Published var process = ProcessMetrics()
    @Published var transfer: OperationMetrics?
}
