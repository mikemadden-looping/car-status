import CryptoKit
import Foundation

/// Talks to the same server the Kia Access app uses in the US
/// (api.owners.kia.com). Based on the open-source hyundai_kia_connect_api
/// project's KiaUvoApiUSA, which documents the requests.
///
/// Sign-in: email + password. The first time on a new device Kia asks for a
/// one-time code (email or text); verifying it returns a "remember me" token
/// (rmtoken) that later sign-ins send instead, so the widget can renew its
/// session on its own.
final class KiaClient {
    static let shared = KiaClient()

    struct OTPChallenge {
        let otpKey: String
        let xid: String
        let email: String?
        let phone: String?
        let hasEmail: Bool
        let hasPhone: Bool
    }

    enum LoginResult {
        case signedIn
        case needsCode(OTPChallenge)
    }

    private struct Session: Codable {
        let sid: String
        let validUntil: Date
    }

    private enum KiaAPIError: Error { case sessionInvalid }

    private let base = URL(string: "https://api.owners.kia.com/apigw/v1/")!
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        urlSession = URLSession(configuration: config)
    }

    // MARK: Device identity

    private var deviceID: String {
        if let id = Keychain.string(Keys.kiaDeviceID) { return id }
        let id = UUID().uuidString.uppercased()
        Keychain.set(id, for: Keys.kiaDeviceID)
        return id
    }

    private func headers(sid: String? = nil, vinKey: String? = nil) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        var h = [
            "content-type": "application/json;charset=utf-8",
            "accept": "application/json",
            "accept-language": "en-US,en;q=0.9",
            "accept-charset": "utf-8",
            "apptype": "L",
            "appversion": "7.22.0",
            "clientid": "SPACL716-APL",
            "clientuuid": Self.uuid5(dnsName: deviceID),
            "from": "SPA",
            "language": "0",
            "offset": String(TimeZone.current.secondsFromGMT() / 3600),
            "ostype": "iOS",
            "osversion": "15.8.5",
            "phonebrand": "iPhone",
            "secretkey": "sydnat-9kykci-Kuhtep-h5nK",
            "to": "APIGW",
            "tokentype": "A",
            "user-agent": "KIAPrimo_iOS/37 CFNetwork/1335.0.3.4 Darwin/21.6.0",
            "date": formatter.string(from: .now),
            "deviceid": deviceID,
        ]
        if let sid { h["sid"] = sid }
        if let vinKey { h["vinkey"] = vinKey }
        return h
    }

    private func send(_ path: String, method: String = "POST", body: [String: Any]? = nil,
                      headers extra: [String: String]) async throws -> ([String: Any], HTTPURLResponse) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        extra.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CarError.badResponse("Kia: no response") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        lastRaw = String(data: data, encoding: .utf8)
        return (json, http)
    }

    /// Last raw reply from Kia, for the Diagnostics screen.
    private(set) var lastRaw: String?

    private func checkStatus(_ json: [String: Any]) throws {
        let code = jsonNumber(jsonValue(json, "status.statusCode")) ?? 0
        guard code != 0 else { return }
        let errorCode = Int(jsonNumber(jsonValue(json, "status.errorCode")) ?? 0)
        if errorCode == 1003 || errorCode == 1005 { throw KiaAPIError.sessionInvalid }
        let message = jsonValue(json, "status.errorMessage") as? String ?? "error \(errorCode)"
        throw CarError.badResponse("Kia: \(message)")
    }

    // MARK: Sign-in

    var hasCredentials: Bool {
        Keychain.string(Keys.kiaEmail) != nil && Keychain.string(Keys.kiaPassword) != nil
    }

    var isSignedIn: Bool { Keychain.string(Keys.kiaRememberToken) != nil || storedSession != nil }

    func signOut() {
        Keychain.set(nil as Data?, for: Keys.kiaSession)
        Keychain.set(nil as Data?, for: Keys.kiaRememberToken)
        Keychain.set(nil as Data?, for: Keys.kiaVehicleID)
    }

    private var storedSession: Session? {
        guard let s = Keychain.codable(Session.self, Keys.kiaSession), s.validUntil > .now else { return nil }
        return s
    }

    private func store(sid: String) {
        // Kia sessions last about a day; renew a bit early.
        Keychain.set(codable: Session(sid: sid, validUntil: .now.addingTimeInterval(22 * 3600)), for: Keys.kiaSession)
    }

    /// Signs in with the stored email/password (and rmtoken if there is one).
    func login() async throws -> LoginResult {
        guard let email = Keychain.string(Keys.kiaEmail),
              let password = Keychain.string(Keys.kiaPassword) else { throw CarError.notSetUp("Kia") }
        var h = headers()
        if let rm = Keychain.string(Keys.kiaRememberToken) { h["rmtoken"] = rm }
        let body: [String: Any] = [
            "deviceKey": deviceID,
            "deviceType": 2,
            "userCredential": ["userId": email, "password": password],
            "tncFlag": 1,
        ]
        let (json, http) = try await send("prof/authUser", body: body, headers: h)
        if let sid = http.value(forHTTPHeaderField: "sid"), !sid.isEmpty {
            store(sid: sid)
            return .signedIn
        }
        if let payload = json["payload"] as? [String: Any], let otpKey = payload["otpKey"] as? String {
            return .needsCode(OTPChallenge(
                otpKey: otpKey,
                xid: http.value(forHTTPHeaderField: "xid") ?? "",
                email: payload["email"] as? String,
                phone: payload["phone"] as? String,
                hasEmail: jsonBool(payload["hasEmail"]) ?? false,
                hasPhone: jsonBool(payload["hasPhone"]) ?? false))
        }
        if Int(jsonNumber(jsonValue(json, "status.errorCode")) ?? 0) == 1001 {
            throw CarError.badResponse("Kia: wrong email or password")
        }
        try checkStatus(json)
        throw CarError.badResponse("Kia: sign-in didn't return a session. See Diagnostics.")
    }

    func sendCode(_ challenge: OTPChallenge, byText: Bool) async throws {
        var h = headers()
        h["otpkey"] = challenge.otpKey
        h["notifytype"] = byText ? "SMS" : "EMAIL"
        h["xid"] = challenge.xid
        let (json, _) = try await send("cmm/sendOTP", body: [:], headers: h)
        try checkStatus(json)
    }

    func verifyCode(_ challenge: OTPChallenge, code: String) async throws {
        guard let email = Keychain.string(Keys.kiaEmail),
              let password = Keychain.string(Keys.kiaPassword) else { throw CarError.notSetUp("Kia") }
        var h = headers()
        h["otpkey"] = challenge.otpKey
        h["xid"] = challenge.xid
        let (json, http) = try await send("cmm/verifyOTP", body: ["otp": code.trimmingCharacters(in: .whitespaces)], headers: h)
        try checkStatus(json)
        guard let sid = http.value(forHTTPHeaderField: "sid"),
              let rmtoken = http.value(forHTTPHeaderField: "rmtoken") else {
            throw CarError.badResponse("Kia: code accepted but no token came back")
        }
        Keychain.set(rmtoken, for: Keys.kiaRememberToken)

        var h2 = headers(sid: sid)
        h2["rmtoken"] = rmtoken
        let body: [String: Any] = [
            "deviceKey": deviceID,
            "deviceType": 2,
            "userCredential": ["userId": email, "password": password],
        ]
        let (_, http2) = try await send("prof/authUser", body: body, headers: h2)
        guard let finalSid = http2.value(forHTTPHeaderField: "sid") else {
            throw CarError.badResponse("Kia: sign-in didn't finish. See Diagnostics.")
        }
        store(sid: finalSid)
    }

    private func currentSID() async throws -> String {
        if let s = storedSession { return s.sid }
        switch try await login() {
        case .signedIn:
            guard let s = storedSession else { throw CarError.needsKiaCode }
            return s.sid
        case .needsCode:
            throw CarError.needsKiaCode
        }
    }

    // MARK: Status

    func fetch() async throws -> (CarStatus, raw: String) {
        guard hasCredentials else { throw CarError.notSetUp("Kia") }
        do {
            return try await fetchOnce(sid: currentSID())
        } catch KiaAPIError.sessionInvalid {
            Keychain.set(nil as Data?, for: Keys.kiaSession)
            do {
                return try await fetchOnce(sid: currentSID())
            } catch KiaAPIError.sessionInvalid {
                throw CarError.needsKiaCode
            }
        }
    }

    private func fetchOnce(sid: String) async throws -> (CarStatus, raw: String) {
        // The vehicle key changes with each session, so look it up every time.
        let (list, _) = try await send("ownr/gvl", method: "GET", headers: headers(sid: sid))
        try checkStatus(list)
        let vehicles = jsonValue(list, "payload.vehicleSummary") as? [[String: Any]] ?? []
        let savedID = Keychain.string(Keys.kiaVehicleID)
        guard let vehicle = vehicles.first(where: { "\($0["vehicleIdentifier"] ?? "")" == savedID }) ?? vehicles.first,
              let key = vehicle["vehicleKey"] as? String else {
            throw CarError.badResponse("Kia: no vehicles on this account yet")
        }
        if let id = vehicle["vehicleIdentifier"] { Keychain.set("\(id)", for: Keys.kiaVehicleID) }

        let body: [String: Any] = [
            "vehicleConfigReq": ["airTempRange": "0", "maintenance": "0", "seatHeatCoolOption": "0",
                                 "vehicle": "1", "vehicleFeature": "0"],
            "vehicleInfoReq": ["drivingActivty": "0", "dtc": "0", "enrollment": "0", "functionalCards": "0",
                               "location": "0", "vehicleStatus": "1", "weather": "0"],
            "vinKey": [key],
        ]
        let (info, _) = try await send("cmm/gvi", body: body, headers: headers(sid: sid, vinKey: key))
        try checkStatus(info)
        let raw = lastRaw ?? ""
        guard let state = jsonValue(info, "payload.vehicleInfoList.0") else {
            throw CarError.badResponse("Kia: no status in reply. See Diagnostics.")
        }

        let vs = "lastVehicleInfo.vehicleStatusRpt.vehicleStatus"
        var car = CarStatus(name: "EV3")
        car.batteryPercent = jsonNumber(jsonValue(state, "\(vs).evStatus.batteryStatus"))
        car.isCharging = jsonBool(jsonValue(state, "\(vs).evStatus.batteryCharge"))
        car.isPluggedIn = jsonBool(jsonValue(state, "\(vs).evStatus.batteryPlugin"))
        car.isLocked = jsonBool(jsonValue(state, "\(vs).doorLock"))
        car.climateOn = jsonBool(jsonValue(state, "\(vs).climate.airCtrl"))
        if let range = jsonNumber(jsonValue(state, "\(vs).evStatus.drvDistance.0.rangeByFuel.evModeRange.value")) {
            let unit = Int(jsonNumber(jsonValue(state, "\(vs).evStatus.drvDistance.0.rangeByFuel.evModeRange.unit")) ?? 3)
            car.rangeMiles = unit == 1 ? range / 1.609344 : range
        }
        if let miles = jsonNumber(jsonValue(state, "vehicleConfig.vehicleDetail.vehicle.mileage")), miles > 0 {
            car.odometerMiles = miles
        }
        if let minutes = jsonNumber(jsonValue(state, "\(vs).evStatus.remainChargeTime.0.timeInterval.value")), minutes > 0 {
            car.chargeMinutesLeft = Int(minutes)
        }
        if let stamp = jsonValue(state, "\(vs).syncDate.utc") as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMddHHmmss"
            car.reportedAt = f.date(from: stamp)
        }
        car.fetchedAt = .now
        return (car, raw)
    }

    // MARK: UUID v5 (what Kia's iOS app sends as clientuuid)

    private static func uuid5(dnsName name: String) -> String {
        let namespace: [UInt8] = [0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
                                  0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
        var bytes = Array(Insecure.SHA1.hash(data: Data(namespace + Array(name.utf8)))).prefix(16).map { $0 }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let u = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: u).uuidString.lowercased()
    }
}
