import CueCore
import Foundation
import Observation

// Asks GitHub for the latest release; the model decides when, so concert never calls it.
@MainActor
@Observable
final class UpdateChecker {
    nonisolated static let timeoutSeconds: TimeInterval = 10

    let running = AppInfo.version.flatMap(AppVersion.init)
    private(set) var checking = false
    private(set) var result: Result<Update.Verdict, Update.Failure>?
    @ObservationIgnored private var task: Task<Void, Never>?

    func check() {
        guard !checking else { return }
        checking = true
        Log.info("update check")
        task = Task { [weak self, running] in
            let outcome = await Self.fetch(running: running)
            // A cancelled check (concert mode) leaves the last result alone.
            guard !Task.isCancelled else { return }
            self?.finish(outcome)
        }
    }

    func cancel() {
        guard checking else { return }
        task?.cancel()
        task = nil
        checking = false
        Log.info("update check cancelled")
    }

    private func finish(_ outcome: Result<Update.Verdict, Update.Failure>) {
        result = outcome
        checking = false
        switch outcome {
        case .success(.upToDate): Log.info("update check: up to date")
        case .success(.available(let version, let url)): Log.info("update check: v\(version) available, \(url)")
        case .failure(let failure): Log.info("update check failed: \(failure)")
        }
    }

    private nonisolated static func fetch(running: AppVersion?) async -> Result<Update.Verdict, Update.Failure> {
        guard let running, let repository = AppInfo.updateRepository, !repository.isEmpty,
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else { return .failure(.notConfigured) }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects a request without a user agent.
        request.setValue("\(AppInfo.name)/\(running)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                return .failure(.http(status))
            }
            let release = try Update.release(from: data)
            return .success(Update.verdict(running: running, latest: release))
        } catch let failure as Update.Failure {
            return .failure(failure)
        } catch {
            Log.info("update check: \(error.localizedDescription)")
            return .failure(.network)
        }
    }
}
