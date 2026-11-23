import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var kiaEmail = Keychain.string(Keys.kiaEmail) ?? ""
    @State private var kiaPassword = Keychain.string(Keys.kiaPassword) ?? ""
    @State private var abrpKey = Keychain.string(Keys.abrpAPIKey) ?? ""
    @State private var abrpToken = Keychain.string(Keys.abrpUserToken) ?? ""
    @State private var id4Capacity = Keychain.string(Keys.id4CapacityKWh) ?? ""
    @State private var ev3Capacity = Keychain.string(Keys.ev3CapacityKWh) ?? ""

    @State private var challenge: KiaClient.OTPChallenge?
    @State private var code = ""
    @State private var codeSent = false
    @State private var kiaMessage: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $kiaEmail)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $kiaPassword)
                        .textContentType(.password)
                    Button(KiaClient.shared.isSignedIn ? "Sign in again" : "Sign in") { signIn() }
                        .disabled(kiaEmail.isEmpty || kiaPassword.isEmpty || working)
                    if KiaClient.shared.isSignedIn && challenge == nil {
                        Button("Sign out of Kia", role: .destructive) {
                            KiaClient.shared.signOut()
                            kiaMessage = "Signed out."
                        }
                    }
                } header: {
                    Text("Kia (EV3)")
                } footer: {
                    Text("Your Kia Access account. Stored only in this phone's keychain.")
                }

                if let challenge {
                    Section("Kia sign-in code") {
                        if !codeSent {
                            if challenge.hasEmail {
                                Button("Email a code to \(challenge.email ?? "your email")") { send(challenge, text: false) }
                            }
                            if challenge.hasPhone {
                                Button("Text a code to \(challenge.phone ?? "your phone")") { send(challenge, text: true) }
                            }
                        } else {
                            TextField("Code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("Verify") { verify(challenge) }
                                .disabled(code.isEmpty || working)
                        }
                    }
                }

                if let kiaMessage {
                    Section { Text(kiaMessage).font(.callout) }
                }

                Section {
                    SecureField("Telemetry API key", text: $abrpKey)
                    SecureField("User token", text: $abrpToken)
                } header: {
                    Text("ABRP (ID.4)")
                } footer: {
                    Text("The API key is the one Iternio emailed you. The user token comes from ABRP's Live Data setup for your ID.4 (the Generic / API token option).")
                }

                Section {
                    LabeledContent("ID.4") {
                        TextField("\(Efficiency.defaultID4Capacity, specifier: "%.1f")", text: $id4Capacity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("EV3") {
                        TextField("\(Efficiency.defaultEV3Capacity, specifier: "%.1f")", text: $ev3Capacity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Usable battery (kWh)")
                } footer: {
                    Text("Used to turn battery-percent drops into kWh for the kWh/mi figure. Leave blank for the defaults: 77 kWh for the 2021 ID.4 Pro S, 81.4 kWh for the EV3 Land.")
                }

                Section("Diagnostics") {
                    NavigationLink("Last ABRP reply") { RawView(title: "ABRP", text: model.abrpRaw) }
                    NavigationLink("Last Kia reply") { RawView(title: "Kia", text: model.kiaRaw) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveFields(); dismiss() }
                }
            }
            .disabled(working)
        }
    }

    private func saveFields() {
        Keychain.set(kiaEmail, for: Keys.kiaEmail)
        Keychain.set(kiaPassword, for: Keys.kiaPassword)
        Keychain.set(abrpKey, for: Keys.abrpAPIKey)
        Keychain.set(abrpToken, for: Keys.abrpUserToken)
        Keychain.set(Double(id4Capacity).map { String($0) }, for: Keys.id4CapacityKWh)
        Keychain.set(Double(ev3Capacity).map { String($0) }, for: Keys.ev3CapacityKWh)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        Task {
            do { try await work() } catch { kiaMessage = error.localizedDescription }
            working = false
        }
    }

    private func signIn() {
        saveFields()
        challenge = nil
        codeSent = false
        code = ""
        run {
            switch try await KiaClient.shared.login() {
            case .signedIn:
                kiaMessage = "Signed in to Kia."
            case .needsCode(let c):
                challenge = c
                kiaMessage = "Kia wants to confirm it's you. Pick where to send a code."
            }
        }
    }

    private func send(_ c: KiaClient.OTPChallenge, text: Bool) {
        run {
            try await KiaClient.shared.sendCode(c, byText: text)
            codeSent = true
            kiaMessage = "Code sent."
        }
    }

    private func verify(_ c: KiaClient.OTPChallenge) {
        run {
            try await KiaClient.shared.verifyCode(c, code: code)
            challenge = nil
            kiaMessage = "Signed in to Kia. This phone is remembered, so the widget can keep itself signed in."
            await model.refresh()
        }
    }
}

struct RawView: View {
    let title: String
    let text: String?

    var body: some View {
        ScrollView {
            Text(text ?? "Nothing yet. Refresh on the main screen first.")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .toolbar {
            if let text {
                ShareLink(item: text)
            }
        }
    }
}
