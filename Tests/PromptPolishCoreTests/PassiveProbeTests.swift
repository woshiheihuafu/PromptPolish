import AppKit
import ApplicationServices
@testable import PromptPolishUI

@MainActor
final class PassiveProbeTests {
    final class BlockingProbe: @unchecked Sendable {
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls: [pid_t] = []
        var recorded: [pid_t] { lock.lock(); defer { lock.unlock() }; return calls }
        func read(_ pid: pid_t) -> PassiveAXTarget? {
            lock.lock(); calls.append(pid); lock.unlock()
            if pid == 1 { _ = gate.wait(timeout: .now() + 2) }
            let element = AXUIElementCreateApplication(pid)
            return PassiveAXTarget(pid: pid, element: element, window: element, canWrite: true, rawFrame: CGRect(x: 1, y: 2, width: 300, height: 100))
        }
    }
    func testPassiveProbeDoesNotBlockUIAndCoalescesNewestTarget() async {
        let probe = BlockingProbe()
        let tracker = PassiveTargetTracker(probe: { pid, _ in probe.read(pid) })
        var delivered: [pid_t] = []
        tracker.request(pid: 1) { if let result = $0 { delivered.append(result.pid) } }
        await eventually { probe.recorded == [1] }
        expectTrue(delivered.isEmpty, "Main actor must continue while AX worker is pending")
        tracker.request(pid: 2) { if let result = $0 { delivered.append(result.pid) } }
        tracker.request(pid: 3) { if let result = $0 { delivered.append(result.pid) } }
        probe.gate.signal()
        await eventually { delivered == [3] }
        expectEqual(probe.recorded, [1, 3])
        expectEqual(delivered, [3])
    }
    func testCancelledProbeCannotOverwriteFreshCapture() async {
        let probe = BlockingProbe()
        let tracker = PassiveTargetTracker(probe: { pid, _ in probe.read(pid) })
        var delivered: [pid_t] = []
        tracker.request(pid: 1) { if let result = $0 { delivered.append(result.pid) } }
        await eventually { probe.recorded == [1] }
        tracker.cancel()
        tracker.request(pid: 4) { if let result = $0 { delivered.append(result.pid) } }
        probe.gate.signal()
        await eventually { delivered == [4] }
        expectEqual(delivered, [4])
        expectEqual(probe.recorded, [1, 4])
    }

    func testCachedHandlesAreDiscardedOnForegroundChangeAndCapture() async {
        final class Probe: @unchecked Sendable {
            let lock = NSLock()
            var preferred: [pid_t?] = []
            func read(_ pid: pid_t, _ cached: PassiveAXTarget?) -> PassiveAXTarget? {
                lock.lock(); preferred.append(cached?.pid); lock.unlock()
                let element = AXUIElementCreateApplication(pid)
                return PassiveAXTarget(pid: pid, element: element, window: element, canWrite: true, rawFrame: CGRect(x: 1, y: 2, width: 300, height: 100))
            }
            var recorded: [pid_t?] { lock.lock(); defer { lock.unlock() }; return preferred }
        }
        let probe = Probe()
        let tracker = PassiveTargetTracker(probe: { probe.read($0, $1) })
        var deliveries = 0
        tracker.request(pid: 1) { _ in deliveries += 1 }
        await eventually { deliveries == 1 }
        tracker.request(pid: 1) { _ in deliveries += 1 }
        await eventually { deliveries == 2 }
        tracker.request(pid: 2) { _ in deliveries += 1 }
        await eventually { deliveries == 3 }
        tracker.cancel()
        tracker.request(pid: 2) { _ in deliveries += 1 }
        await eventually { deliveries == 4 }
        expectEqual(probe.recorded, [nil, 1, nil, nil])
    }
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fail("Passive probe did not reach expected state")
    }
}
