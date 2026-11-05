import Darwin
import Foundation
import Observation
import OSLog

/// How hard macOS is asking apps to give memory back.
nonisolated enum MemoryPressure: Sendable {
    case warning
    case critical
}

/// Reads how much memory the app uses, the same number Activity Monitor shows, and passes on
/// macOS's memory-pressure warnings so caches can be let go before the system has to swap.
@Observable
final class MemoryMonitor {
    /// The app's memory footprint in bytes, as of the last `refresh()`.
    private(set) var footprint: UInt64 = 0

    /// Called on the main thread when macOS reports memory pressure.
    @ObservationIgnored var onPressure: ((MemoryPressure) -> Void)?
    @ObservationIgnored private var source: (any DispatchSourceMemoryPressure)?
    private let log = Logger(subsystem: Log.subsystem, category: "memory")

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.source?.data else { return }
                let pressure: MemoryPressure = event.contains(.critical) ? .critical : .warning
                self.log.notice("Memory pressure: \(String(describing: pressure), privacy: .public)")
                self.onPressure?(pressure)
            }
        }
        source.resume()
        self.source = source
    }

    func refresh() {
        if let bytes = Self.currentFootprint() {
            footprint = bytes
        }
    }

    /// The physical footprint from the kernel: what Activity Monitor's Memory column shows.
    nonisolated static func currentFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
