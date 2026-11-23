import SwiftUI
import WidgetKit

struct CarEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CarEntry {
        CarEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        completion(CarEntry(date: .now, snapshot: context.isPreview ? .sample : (Snapshot.cached ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        Task {
            let result = await StatusStore.refresh()
            let entry = CarEntry(date: .now, snapshot: result.snapshot)
            // iOS decides the real cadence; this asks for roughly every 20 minutes.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(20 * 60))))
        }
    }
}

struct CarStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CarEntry

    private var cars: [CarStatus] {
        [entry.snapshot.id4 ?? CarStatus(name: "ID.4"), entry.snapshot.ev3 ?? CarStatus(name: "EV3")]
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(cars.map { "\($0.name) \($0.percentText)" }.joined(separator: " · "))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(cars, id: \.name) { car in
                    HStack(spacing: 4) {
                        Text(car.name).font(.headline)
                        Spacer(minLength: 2)
                        if car.isCharging == true { Image(systemName: "bolt.fill") }
                        Text(car.percentText).font(.headline)
                    }
                }
            }
        case .systemMedium:
            HStack(spacing: 16) {
                ForEach(cars, id: \.name) { car in MediumCar(car: car) }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(cars, id: \.name) { car in SmallCar(car: car) }
            }
        }
    }
}

private struct SmallCar: View {
    let car: CarStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(car.name).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if car.error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                Image(systemName: car.stateIcon)
                    .foregroundStyle(car.isCharging == true ? .green : .secondary)
            }
            .font(.caption)
            Text(car.percentText).font(.system(.title2, design: .rounded).bold())
            BatteryBar(car: car, height: 6)
        }
    }
}

private struct MediumCar: View {
    let car: CarStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(car.name).font(.headline)
                Spacer(minLength: 0)
                if car.isLocked == false { Image(systemName: "lock.open.fill").foregroundStyle(.orange) }
                if car.error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(car.percentText).font(.system(.largeTitle, design: .rounded).bold())
                    .minimumScaleFactor(0.6)
                if let range = car.rangeText {
                    Text(range).font(.caption).foregroundStyle(.secondary)
                }
            }
            BatteryBar(car: car, height: 8)
            Label(car.isCharging == true ? "Charging" : (car.isPluggedIn == true ? "Plugged in" : "Unplugged"),
                  systemImage: car.stateIcon)
                .font(.caption)
                .foregroundStyle(car.isCharging == true ? .green : .secondary)
            if let when = car.reportedAt {
                Text(when, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CarStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarStatus", provider: Provider()) { entry in
            CarStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cars")
        .description("Battery and charging for the ID.4 and EV3.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CarStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarStatusWidget()
    }
}
