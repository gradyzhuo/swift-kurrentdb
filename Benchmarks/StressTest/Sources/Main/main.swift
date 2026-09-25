import Foundation
import KurrentDB
import StressTest

// MARK: - Main
@main
struct StressTestExecutable {
    static func main() async {
        let config = Config.fromEnv()
        let runId = UUID().uuidString
        var results: [StepResult] = []
        var consecutiveSaturated = 0

        let settings = ClientSettings.localhost()
            .authenticated(.credentials(username: "admin", password: "changeit"))
        let client = KurrentDBClient(settings: settings)

        do {
            for vuCount in config.steps {
                print("Running step with \(vuCount) VUs...")

                // Warmup: 5 seconds with existing VUs
                _ = await runStressTest(client: client, vus: vuCount, config: config, duration: config.warmupDuration)

                // Measurement: 30 seconds, collect metrics
                var stepResult = await runStressTest(client: client, vus: vuCount, config: config, duration: config.stepDuration)

                // Compute saturation
                let saturated = isSaturated(
                    write: stepResult.write,
                    read: stepResult.read,
                    vus: vuCount,
                    targetWriteRate: config.writeRate,
                    targetReadRate: config.readRate
                )
                stepResult = StepResult(vus: vuCount, write: stepResult.write, read: stepResult.read, saturated: saturated)
                results.append(stepResult)

                print("  VUs: \(vuCount), Saturated: \(stepResult.saturated)")

                // Check saturation rule: stop after 2 consecutive saturated steps
                if stepResult.saturated {
                    consecutiveSaturated += 1
                    if consecutiveSaturated >= 2 {
                        print("Two consecutive saturated steps. Stopping.")
                        break
                    }
                } else {
                    consecutiveSaturated = 0
                }
            }

            let report = Report(label: config.label, runId: runId, steps: results)
            let encoded = try JSONEncoder().encode(report)
            try encoded.write(to: URL(fileURLWithPath: config.outputFile))
            print("Results written to \(config.outputFile)")

        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
    }
}
