import Foundation

/// Reads the ID.4's latest live data from A Better Routeplanner's Telemetry API
/// (`get_telemetry`), which ABRP gets from the car through its Enode link.
enum ABRPClient {
    static func fetch() async throws -> (CarStatus, raw: String) {
        guard let apiKey = Keychain.string(Keys.abrpAPIKey),
              let token = Keychain.string(Keys.abrpUserToken) else {
            throw CarError.notSetUp("ABRP")
        }
        var components = URLComponents(string: "https://api.iternio.com/1/tlm/get_telemetry")!
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("APIKEY \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let raw = String(data: data, encoding: .utf8) ?? ""
        let json = try? JSONSerialization.jsonObject(with: data)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0

        if let status = jsonValue(json, "status") as? String, status != "ok" {
            throw CarError.badResponse("ABRP: \(status) \(jsonValue(json, "error") ?? "")")
        }
        guard code == 200, let tlm = findTelemetry(in: json) else {
            throw CarError.badResponse("ABRP returned no telemetry (HTTP \(code)). See Diagnostics.")
        }

        var car = CarStatus(name: "ID.4")
        car.batteryPercent = jsonNumber(tlm["soc"])
        if let km = jsonNumber(tlm["est_battery_range"]) { car.rangeMiles = km / 1.609344 }
        car.isCharging = jsonBool(tlm["is_charging"])
        if let km = jsonNumber(tlm["odometer"]), km > 0 { car.odometerMiles = km / 1.609344 }
        car.energyKWh = jsonNumber(tlm["soe"])
        if let utc = jsonNumber(tlm["utc"]) {
            // epoch seconds per the docs; tolerate milliseconds too
            car.reportedAt = Date(timeIntervalSince1970: utc > 10_000_000_000 ? utc / 1000 : utc)
        }
        car.fetchedAt = .now
        return (car, raw)
    }

    /// The response shape for get_telemetry isn't documented, so take the
    /// first object anywhere in the reply that has a "soc" field.
    private static func findTelemetry(in value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if dict["soc"] != nil { return dict }
            for key in ["result", "telemetry", "tlm"] {
                if let found = findTelemetry(in: dict[key]) { return found }
            }
            for (_, child) in dict { if let found = findTelemetry(in: child) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = findTelemetry(in: child) { return found } }
        }
        return nil
    }
}
