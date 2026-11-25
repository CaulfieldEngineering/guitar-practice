import Foundation

// Stand-ins for what the model code borrows from the app's Apple-only parts, so it builds with the Swift toolchain
// on Windows (scripts/model-check.sh). Never part of the app.
final class Locked<T> {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func with<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
    @discardableResult
    func tryWith(_ body: (inout T) -> Void) -> Bool { guard lock.try() else { return false }; defer { lock.unlock() }; body(&value); return true }
    var current: T { with { $0 } }
}
