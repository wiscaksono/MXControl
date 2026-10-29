import Foundation

/// Remembers whether the permission wizard was completed. Kept behind a small
/// protocol so tests get a deterministic value instead of shared defaults.
public protocol OnboardingStore: Sendable {
    var isFinished: Bool { get }
    func markFinished()
}

public final class UserDefaultsOnboardingStore: OnboardingStore, @unchecked Sendable {
    private let key: String

    public init(key: String = "onboardingFinished") {
        self.key = key
    }

    public var isFinished: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public func markFinished() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

public final class InMemoryOnboardingStore: OnboardingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var finished: Bool

    public init(finished: Bool = true) {
        self.finished = finished
    }

    public var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    public func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }
}
