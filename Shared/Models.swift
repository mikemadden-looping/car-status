import Foundation

/// What the widget and app show for one car.
struct CarStatus: Codable, Equatable {
    var name: String
    var batteryPercent: Double?
    var rangeMiles: Double?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var isLocked: Bool?
    var climateOn: Bool?
    var chargeMinutesLeft: Int?
    var odometerMiles: Double?
    /// Energy left in the pack, when the source reports it directly (ABRP's "soe").
    var energyKWh: Double?
    /// Miles driven since the last charge, and average consumption over them.
    var milesSinceCharge: Double?
    var kwhPerMile: Double?
    /// When the car last reported this data.
    var reportedAt: Date?
    /// When this app last fetched successfully.
    var fetchedAt: Date?
    /// Set when the most recent fetch failed; the other fields keep the last good values.
    var error: String?
}

struct Snapshot: Codable, Equatable {
    var id4: CarStatus?
    var ev3: CarStatus?

    static var cached: Snapshot? { Keychain.codable(Snapshot.self, Keys.snapshot) }

    static let sample = Snapshot(
        id4: CarStatus(name: "ID.4", batteryPercent: 72, rangeMiles: 181, isCharging: false,
                       isPluggedIn: false, reportedAt: .now.addingTimeInterval(-1200)),
        ev3: CarStatus(name: "EV3", batteryPercent: 64, rangeMiles: 165, isCharging: true,
                       isPluggedIn: true, isLocked: true, chargeMinutesLeft: 95,
                       reportedAt: .now.addingTimeInterval(-600))
    )
}

enum CarError: LocalizedError {
    case notSetUp(String)
    case needsKiaCode
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp(let what): return "\(what) isn't set up yet. Open Settings in the app."
        case .needsKiaCode: return "Kia needs a new sign-in code. Open Settings in the app."
        case .badResponse(let detail): return detail
        }
    }
}

/// Looks up a dotted path like "a.b.0.c" in decoded JSON.
func jsonValue(_ root: Any?, _ path: String) -> Any? {
    var current = root
    for part in path.split(separator: ".") {
        if let index = Int(part), let array = current as? [Any] {
            current = index < array.count ? array[index] : nil
        } else if let dict = current as? [String: Any] {
            current = dict[String(part)]
        } else {
            return nil
        }
    }
    return current is NSNull ? nil : current
}

func jsonNumber(_ value: Any?) -> Double? {
    switch value {
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

func jsonBool(_ value: Any?) -> Bool? {
    switch value {
    case let n as NSNumber: return n.doubleValue != 0
    case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
    default: return nil
    }
}
