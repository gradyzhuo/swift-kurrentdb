@testable import LiveBenchCore
import Testing

@Suite("Process usage")
struct ProcessUsageTests {
    /// /proc/<pid>/status separates the key from its value with a tab and pads with spaces.
    @Test func peakResidentReadsVmHWMInBytes() {
        let status = "Name:\tdriver\nVmPeak:\t  900000 kB\nVmHWM:\t   58436 kB\nVmRSS:\t   41000 kB\n"
        let peak = ProcessUsage.peakResident(fromStatus: status)
        #expect(peak == UInt64(58436 * 1024))
    }

    @Test func peakResidentWithoutAUsableVmHWMLineIsNil() {
        for status in ["Name:\tdriver\nVmRSS:\t41000 kB\n", "VmHWM:\tmany kB\n", "VmHWM:\t58436 MB\n"] {
            let peak = ProcessUsage.peakResident(fromStatus: status)
            #expect(peak == nil, "\(status)")
        }
    }

    @Test func currentReportsAPeak() {
        #expect(ProcessUsage.current().maxRss > 0)
    }
}
