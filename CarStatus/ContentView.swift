import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CarCard(car: model.snapshot.id4 ?? CarStatus(name: "ID.4"))
                    CarCard(car: model.snapshot.ev3 ?? CarStatus(name: "EV3"))
                    Text("ID.4 data comes from ABRP; EV3 data from Kia. Pull down to refresh.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Cars")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.isRefreshing { ProgressView() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await model.refresh() } }) {
                SettingsView()
            }
        }
    }
}

struct CarCard: View {
    let car: CarStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(car.name).font(.title2.bold())
                Spacer()
                if let locked = car.isLocked {
                    Label(locked ? "Locked" : "Unlocked", systemImage: locked ? "lock.fill" : "lock.open.fill")
                        .font(.subheadline)
                        .foregroundStyle(locked ? Color.secondary : Color.orange)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(car.percentText).font(.system(size: 44, weight: .bold, design: .rounded))
                if let range = car.rangeText {
                    Text(range).font(.title3).foregroundStyle(.secondary)
                }
            }
            BatteryBar(car: car)
            Label(car.stateText, systemImage: car.stateIcon)
                .foregroundStyle(car.isCharging == true ? .green : .primary)
            if let since = car.sinceChargeText {
                Label(since, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.subheadline)
            }
            if car.climateOn == true {
                Label("Climate on", systemImage: "fan.fill")
            }
            if let when = car.reportedAt {
                Text("Car reported \(when, style: .relative) ago")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = car.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
