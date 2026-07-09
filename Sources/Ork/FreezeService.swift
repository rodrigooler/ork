import Darwin

/// CPU accounting for a whole PTY process group. Terminal output can't tell
/// "TUI repainting a spinner" from "agent actually working" — only CPU can:
/// repaint is a low steady trickle, real work comes in bursts.
enum ProcessCPU {
    private static let machToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// Total user+system CPU seconds consumed by every live process in the
    /// group (zsh, the agent CLI, and anything they spawned).
    static func groupCPUSeconds(pgid: pid_t) -> Double {
        var pids = [pid_t](repeating: 0, count: 256)
        let bytes = proc_listpids(
            UInt32(PROC_PGRP_ONLY), UInt32(pgid),
            &pids, Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard bytes > 0 else { return 0 }
        var total: UInt64 = 0
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            var info = rusage_info_current()
            let result = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            if result == 0 {
                total += info.ri_user_time + info.ri_system_time
            }
        }
        return Double(total) * machToSeconds
    }
}
