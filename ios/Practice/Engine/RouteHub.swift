import AVFoundation

extension Notification.Name {
    /// The audio route settled after a change: posted once, a moment after the last of a burst of iOS's route
    /// changes. Screens listen to this, never to AVAudioSession.routeChangeNotification itself.
    static let practiceRouteChanged = Notification.Name("practice.routeChanged")
}

/// One listener for iOS's route changes, so the app answers each burst once (0.2.0 had three listeners, each asking
/// iOS for the input again; every ask fired another route change, which they each answered, and with the speaker
/// picked iOS swapped the interface for the phone's microphone each time: the app froze, Joe 2026-11-17: "After
/// trying to select a device a few times, it's basically frozen now").
///
/// - Bursts are coalesced: one `practiceRouteChanged` 0.2 s after the last change.
/// - Asking iOS for an input is limited: the same input at most once every 2 s, and after 3 asks in 10 s that iOS
///   did not follow, the app stops asking until the next pick by hand or the device is plugged in again.
/// - A storm (more than 12 route changes in 3 s) clears the saved output pick, stops asking for 5 s, and leaves one
///   line for the Audio screen (`note`).
/// Main thread only (every caller is: the notifications arrive on the main queue).
enum RouteHub {
    private static var observer: NSObjectProtocol?
    private static var pending: DispatchWorkItem?
    private static var recent: [Double] = []
    private static var asks: [(uid: String, at: Double)] = []
    private static var quietUntil = 0.0
    /// Inputs iOS refused often enough that the app stopped asking (by port id).
    private static var givenUp: Set<String> = []
    private static var lastInputs: Set<String> = []
    /// One line for the screens when the app had to step back.
    private(set) static var note: String?

    static func start() {
        guard observer == nil else { return }
        lastInputs = Set((AVAudioSession.sharedInstance().availableInputs ?? []).map(\.uid))
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            RouteHub.changed()
        }
    }

    private static func changed() {
        let now = CACurrentMediaTime()
        recent = recent.filter { now - $0 < 3 } + [now]
        if recent.count > 12 && now >= quietUntil {
            quietUntil = now + 5
            AudioPrefs.preferredOutput = nil
            note = L.audioKeptSwitching
            recent = []
        }
        // A device plugged in again (or a new one) may be asked for again.
        let inputs = Set((AVAudioSession.sharedInstance().availableInputs ?? []).map(\.uid))
        let added = inputs.subtracting(lastInputs)
        if !added.isEmpty { givenUp.subtract(added) }
        lastInputs = inputs
        pending?.cancel()
        let w = DispatchWorkItem { NotificationCenter.default.post(name: .practiceRouteChanged, object: nil) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: w)
    }

    /// A pick by hand: ask again, whatever happened before.
    static func picked() {
        givenUp.removeAll()
        asks.removeAll()
        quietUntil = 0
        note = nil
    }

    /// Whether the app may ask iOS for this input now; records the ask when it may.
    static func mayAsk(for uid: String) -> Bool {
        let now = CACurrentMediaTime()
        guard now >= quietUntil, !givenUp.contains(uid) else { return false }
        asks = asks.filter { now - $0.at < 10 }
        if let last = asks.last(where: { $0.uid == uid }), now - last.at < 2 { return false }
        if asks.filter({ $0.uid == uid }).count >= 3 {
            givenUp.insert(uid)
            return false
        }
        asks.append((uid, now))
        return true
    }

    /// Whether the app has stopped asking for this input (the screen then says to plug it in again).
    static func gaveUp(on uid: String?) -> Bool { uid.map { givenUp.contains($0) } ?? false }

    /// Whether route changes are coming too fast for the app to touch the session.
    static var quiet: Bool { CACurrentMediaTime() < quietUntil }
}
