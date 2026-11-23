import Foundation

/// Fetches both cars at once and caches the result for the widget.
enum StatusStore {
    struct Result {
        var snapshot: Snapshot
        var abrpRaw: String?
        var kiaRaw: String?
    }

    static func refresh() async -> Result {
        async let id4 = attempt { try await ABRPClient.fetch() }
        async let ev3 = attempt { try await KiaClient.shared.fetch() }
        var (a, k) = await (id4, ev3)
        if a.car != nil { Efficiency.apply(to: &a.car!, anchorKey: Keys.id4Anchor) }
        if k.car != nil { Efficiency.apply(to: &k.car!, anchorKey: Keys.ev3Anchor) }

        let previous = Snapshot.cached
        var snapshot = Snapshot()
        snapshot.id4 = merge(a.car, a.error, previous?.id4, name: "ID.4")
        snapshot.ev3 = merge(k.car, k.error, previous?.ev3, name: "EV3")
        Keychain.set(codable: snapshot, for: Keys.snapshot)
        return Result(snapshot: snapshot, abrpRaw: a.raw ?? a.error, kiaRaw: KiaClient.shared.lastRaw ?? k.error)
    }

    private static func attempt(_ work: () async throws -> (CarStatus, raw: String)) async
        -> (car: CarStatus?, raw: String?, error: String?) {
        do {
            let (car, raw) = try await work()
            return (car, raw, nil)
        } catch {
            return (nil, nil, error.localizedDescription)
        }
    }

    /// On failure keep the last good numbers and attach the error.
    private static func merge(_ fresh: CarStatus?, _ error: String?, _ old: CarStatus?, name: String) -> CarStatus {
        if let fresh { return fresh }
        var car = old ?? CarStatus(name: name)
        car.error = error
        return car
    }
}
