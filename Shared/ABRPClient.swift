import Foundation

/// Reads the ID.4's latest live data from A Better Routeplanner's Telemetry API
/// (`get_telemetry`), which ABRP gets from the car through its Enode link.
enum ABRPClient {
    /// Last raw reply (with HTTP status), kept even when the request fails, for Diagnostics.
    nonisolated(unsafe) static var lastRaw: String?

    private enum RequestStyle: String, CaseIterable {
        case headerKeyPostToken = "key in header, token in POST body"
        case headerKeyQueryToken = "key in header, token in URL"
        case queryOnly = "key and token in URL"

        func request(apiKey: String, token: String) -> URLRequest {
            let base = "https://api.iternio.com/1/tlm/get_telemetry"
            var c = URLComponents(string: base)!
            switch self {
            case .headerKeyPostToken:
                var r = URLRequest(url: c.url!, timeoutInterval: 15)
                r.httpMethod = "POST"
                r.setValue("APIKEY \(apiKey)", forHTTPHeaderField: "Authorization")
                r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                var form = URLComponents()
                form.queryItems = [URLQueryItem(name: "token", value: token)]
                r.httpBody = form.percentEncodedQuery?.data(using: .utf8)
                return r
            case .headerKeyQueryToken:
                c.queryItems = [URLQueryItem(name: "token", value: token)]
                var r = URLRequest(url: c.url!, timeoutInterval: 15)
                r.setValue("APIKEY \(apiKey)", forHTTPHeaderField: "Authorization")
                return r
            case .queryOnly:
                c.queryItems = [URLQueryItem(name: "token", value: token),
                                URLQueryItem(name: "api_key", value: apiKey)]
                return URLRequest(url: c.url!, timeoutInterval: 15)
            }
        }
    }

    static func fetch() async throws -> (CarStatus, raw: String) {
        guard let apiKey = Keychain.string(Keys.abrpAPIKey),
              let token = Keychain.string(Keys.abrpUserToken) else {
            throw CarError.notSetUp("ABRP")
        }
        // ABRP's docs don't pin down how get_telemetry wants credentials, so try
        // the known styles in turn and stop at the first one that isn't a 401.
        var attempts: [(String, Data, Int)] = []
        for style in RequestStyle.allCases {
            let (data, response) = try await URLSession.shared.data(for: style.request(apiKey: apiKey, token: token))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            attempts.append((style.rawValue, data, code))
            if code != 401 && code != 403 { break }
        }
        let (_, data, code) = attempts.last!
        let raw = String(data: data, encoding: .utf8) ?? ""
        let json = try? JSONSerialization.jsonObject(with: data)
        lastRaw = attempts.map { name, d, c in
            let body = String(data: d, encoding: .utf8) ?? ""
            return "[\(name)] HTTP \(c)\n\(body.isEmpty ? "(empty reply)" : body)"
        }.joined(separator: "\n\n")

        if let status = jsonValue(json, "status") as? String, status != "ok" {
            let reason = ["errortext", "error", "message", "msg", "errors", "detail"]
                .compactMap { jsonValue(json, $0).map { "\($0)" } }
                .first ?? String(raw.prefix(200))
            throw CarError.badResponse("ABRP (HTTP \(code)): \(reason)")
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
