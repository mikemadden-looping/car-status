import SwiftUI

extension CarStatus {
    var percentText: String { batteryPercent.map { "\(Int($0.rounded()))%" } ?? "—" }
    var rangeText: String? { rangeMiles.map { "\(Int($0.rounded())) mi" } }

    var stateText: String {
        if isCharging == true {
            if let m = chargeMinutesLeft { return "Charging · \(m / 60)h \(m % 60)m left" }
            return "Charging"
        }
        if isPluggedIn == true { return "Plugged in" }
        return "Not plugged in"
    }

    var stateIcon: String {
        if isCharging == true { return "bolt.fill" }
        if isPluggedIn == true { return "powerplug.fill" }
        return "car.fill"
    }

    var batteryColor: Color {
        guard let p = batteryPercent else { return .secondary }
        if p < 20 { return .red }
        if p < 40 { return .orange }
        return .green
    }
}

/// A horizontal battery bar with the percentage inside.
struct BatteryBar: View {
    let car: CarStatus
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 3)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: height / 3)
                    .fill(car.batteryColor.gradient)
                    .frame(width: geo.size.width * CGFloat(min(max((car.batteryPercent ?? 0) / 100, 0), 1)))
            }
        }
        .frame(height: height)
    }
}
