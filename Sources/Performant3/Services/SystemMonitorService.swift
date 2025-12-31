import Foundation
import Metal
import IOKit

/// Service for monitoring system resources (GPU, Memory, CPU)
@MainActor
class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published var gpuInfo: GPUInfo = GPUInfo()
    @Published var memoryInfo: MemoryInfo = MemoryInfo()
    @Published var cpuUsage: Double = 0
    @Published var isMonitoring = false

    private var monitorTask: Task<Void, Never>?
    private let updateInterval: TimeInterval = 1.0

    struct GPUInfo {
        var name: String = "Unknown"
        var isAvailable: Bool = false
        var metalSupported: Bool = false
        var recommendedMemory: UInt64 = 0
        var currentAllocatedSize: UInt64 = 0
        var peakAllocatedSize: UInt64 = 0
        var utilizationPercent: Double = 0

        var recommendedMemoryGB: Double {
            Double(recommendedMemory) / 1_073_741_824
        }

        var currentAllocatedGB: Double {
            Double(currentAllocatedSize) / 1_073_741_824
        }
    }

    struct MemoryInfo {
        var total: UInt64 = 0
        var used: UInt64 = 0
        var free: UInt64 = 0
        var appUsed: UInt64 = 0

        var totalGB: Double { Double(total) / 1_073_741_824 }
        var usedGB: Double { Double(used) / 1_073_741_824 }
        var freeGB: Double { Double(free) / 1_073_741_824 }
        var appUsedMB: Double { Double(appUsed) / 1_048_576 }
        var usagePercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    }

    // MARK: - Initialization

    init() {
        detectGPU()
    }

    // MARK: - GPU Detection

    private func detectGPU() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            gpuInfo.isAvailable = false
            return
        }

        gpuInfo.name = device.name
        gpuInfo.isAvailable = true
        gpuInfo.metalSupported = true
        gpuInfo.recommendedMemory = device.recommendedMaxWorkingSetSize

        // Check for Apple Silicon features
        #if arch(arm64)
        gpuInfo.name = "\(device.name) (Apple Silicon)"
        #endif
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitorTask = Task {
            while !Task.isCancelled && isMonitoring {
                await updateMetrics()
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func updateMetrics() async {
        // Update memory info
        updateMemoryInfo()

        // Update GPU metrics (limited on macOS without IOKit deep access)
        updateGPUMetrics()

        // Update CPU usage
        updateCPUUsage()
    }

    private func updateMemoryInfo() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryInfo.appUsed = info.resident_size
        }

        // Get system memory
        var stats = vm_statistics64()
        var statsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let hostPort = mach_host_self()
        let vmResult = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &statsCount)
            }
        }

        if vmResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            memoryInfo.free = UInt64(stats.free_count) * pageSize
            memoryInfo.used = UInt64(stats.active_count + stats.inactive_count + stats.wire_count) * pageSize
            memoryInfo.total = memoryInfo.free + memoryInfo.used
        }
    }

    private func updateGPUMetrics() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        // Metal doesn't expose real-time GPU utilization directly
        // We can only get memory-related info
        gpuInfo.currentAllocatedSize = UInt64(device.currentAllocatedSize)

        // Track peak allocation
        if UInt64(device.currentAllocatedSize) > gpuInfo.peakAllocatedSize {
            gpuInfo.peakAllocatedSize = UInt64(device.currentAllocatedSize)
        }

        // Estimate utilization based on allocated memory
        if gpuInfo.recommendedMemory > 0 {
            gpuInfo.utilizationPercent = Double(device.currentAllocatedSize) / Double(gpuInfo.recommendedMemory) * 100
        }
    }

    private func updateCPUUsage() {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t()

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            return
        }

        var totalUsage: Double = 0

        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }

            if result == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))

        cpuUsage = min(totalUsage, 100)
    }

    // MARK: - Queries

    var hasGPU: Bool { gpuInfo.isAvailable }

    var gpuMemoryUsagePercent: Double {
        guard gpuInfo.recommendedMemory > 0 else { return 0 }
        return Double(gpuInfo.currentAllocatedSize) / Double(gpuInfo.recommendedMemory) * 100
    }

    var systemHealthStatus: HealthStatus {
        if memoryInfo.usagePercent > 90 || gpuMemoryUsagePercent > 90 {
            return .critical
        } else if memoryInfo.usagePercent > 75 || gpuMemoryUsagePercent > 75 {
            return .warning
        }
        return .healthy
    }

    enum HealthStatus {
        case healthy, warning, critical

        var color: String {
            switch self {
            case .healthy: return "green"
            case .warning: return "yellow"
            case .critical: return "red"
            }
        }
    }
}

// MARK: - GPU Memory Tracking for Training

extension SystemMonitorService {
    /// Estimate if there's enough GPU memory for a training configuration
    func canFitTraining(batchSize: Int, imageSize: Int, modelParams: Int) -> Bool {
        // Rough estimation: each image takes width * height * 3 (RGB) * 4 (float32) bytes
        let imageMemory = imageSize * imageSize * 3 * 4 * batchSize
        // Model parameters (rough estimate)
        let modelMemory = modelParams * 4 * 2 // weights + gradients

        let estimatedMemory = UInt64(imageMemory + modelMemory)
        let availableMemory = gpuInfo.recommendedMemory - gpuInfo.currentAllocatedSize

        return estimatedMemory < availableMemory
    }

    /// Get recommended batch size for available GPU memory
    func recommendedBatchSize(imageSize: Int, modelParams: Int) -> Int {
        let modelMemory = UInt64(modelParams * 4 * 2)
        let availableForBatches = gpuInfo.recommendedMemory - modelMemory - gpuInfo.currentAllocatedSize
        let perImageMemory = UInt64(imageSize * imageSize * 3 * 4)

        guard perImageMemory > 0 else { return 1 }

        let maxBatch = Int(availableForBatches / perImageMemory)
        // Return power of 2 batch size
        let batchSizes = [1, 2, 4, 8, 16, 32, 64, 128]
        return batchSizes.last(where: { $0 <= maxBatch }) ?? 1
    }
}
