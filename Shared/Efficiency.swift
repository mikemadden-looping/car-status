import Foundation

/// Works out average kWh per mile since the last charge.
///
/// Neither Kia nor ABRP reports this directly, so every fetch is compared with
/// an "anchor": the odometer and battery level saved the last time the car was
/// seen charging (or its battery level went up). Energy used is the drop in
/// battery level times the battery's usable capacity — or, for the ID.4, the
/// drop in ABRP's reported energy (kWh) when it sends that. It includes
/// everything the car spent, climate and overnight drain too, like the car's
/// own "since charge" figure.
enum Efficiency {
    struct Anchor: Codable {
        var odometerMiles: Double
        var batteryPercent: Double
        var energyKWh: Double?
        var date: Date
    }

    /// Battery levels are whole percents, so wait for enough miles that one
    /// percent doesn't swing the average much.
    static let minimumMiles = 10.0

    static let defaultID4Capacity = 77.0   // 2021 ID.4 Pro S usable
    static let defaultEV3Capacity = 81.4   // EV3 long-range pack

    static func capacity(for anchorKey: String) -> Double {
        let isID4 = anchorKey == Keys.id4Anchor
        let stored = Keychain.string(isID4 ? Keys.id4CapacityKWh : Keys.ev3CapacityKWh).flatMap(Double.init)
        return stored ?? (isID4 ? defaultID4Capacity : defaultEV3Capacity)
    }

    static func apply(to car: inout CarStatus, anchorKey: String) {
        guard let odometer = car.odometerMiles, let percent = car.batteryPercent else { return }
        let current = Anchor(odometerMiles: odometer, batteryPercent: percent, energyKWh: car.energyKWh, date: .now)

        guard let anchor = Keychain.codable(Anchor.self, anchorKey),
              car.isCharging != true,
              percent <= anchor.batteryPercent,          // went up → it charged since
              odometer >= anchor.odometerMiles else {
            Keychain.set(codable: current, for: anchorKey)
            car.milesSinceCharge = 0
            return
        }

        let miles = odometer - anchor.odometerMiles
        car.milesSinceCharge = miles
        guard miles >= minimumMiles else { return }

        let used: Double
        if let then = anchor.energyKWh, let now = car.energyKWh, then > now {
            used = then - now
        } else {
            used = (anchor.batteryPercent - percent) / 100 * capacity(for: anchorKey)
        }
        if used > 0 { car.kwhPerMile = used / miles }
    }
}
