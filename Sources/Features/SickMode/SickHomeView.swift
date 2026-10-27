import SwiftUI

/// Home while sick mode is on (boards j4 and j7): the sick card with the day's temperatures, a card
/// per medicine dosed since it started, today's diapers and fluids, and a timeline of what's done
/// and what's due. It replaces the normal Home below the header; running timers still show above
/// the sick card. After a day clear the end prompt leads, and the cards fold down.
struct SickHomeView<Timers: View>: View {
    let childID: Int
    let startedAt: Date
    /// The child's records, newest first.
    let entities: [LocalEntity]
    let unit: TemperatureUnit
    /// The fever line, in `unit`.
    let line: Double
    @ViewBuilder let timers: Timers
    var onLogTemperature: () -> Void
    var onLogDose: (LocalEntity) -> Void
    var onEdit: (LocalEntity) -> Void
    var onSeeAll: () -> Void
    var onEnd: (Analytics.SickModeEnd) -> Void
    var onKeepOn: () -> Void

    @State private var sickMode = SickModeStore.shared
    @State private var colors = MedicineColorStore.shared
    @AppStorage(MedicationReminderPolicy.enabledKey, store: SharedDefaults.suite) private var remindersEnabled = false
    @AppStorage(SickMode.checkHoursKey, store: SharedDefaults.suite) private var checkHours = SickMode.defaultCheckHours
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        // Progress bars and "in 1 hr 10 min" move each minute; a medicine turns OK right at its
        // time, not up to a minute late.
        SwiftUI.TimelineView(.periodic(from: minuteAnchor, by: 60)) { _ in
            SwiftUI.TimelineView(.explicit(dueTimes)) { _ in
                content(now: .now)
            }
        }
    }

    private var doses: [LocalEntity] { entities.filter { $0.kind == .medication } }

    private var dueTimes: [Date] {
        SickMode.medicines(doses, since: startedAt, now: .now).compactMap {
            if case .waiting(let next, _) = $0.phase { next } else { nil }
        }
    }

    /// Minute ticks lined up with the soonest dose, so "in 1 hr 10 min" turns over with its countdown.
    private var minuteAnchor: Date {
        guard let next = dueTimes.min() else { return .now }
        return next.addingTimeInterval(-(next.timeIntervalSinceNow / 60).rounded(.up) * 60)
    }

    private var remindersOn: Bool { remindersEnabled || MedicationReminderPolicy.isEnabled }

    @ViewBuilder private func content(now: Date) -> some View {
        let readings = SickMode.readings(entities, unit: unit)
        let medicines = SickMode.medicines(doses, since: startedAt, now: now)
        let clear = SickMode.isClear(readings: readings, doses: doses, startedAt: startedAt, line: line, now: now)
        VStack(spacing: 18) {
            if SickMode.showsEndPrompt(clear: clear, state: sickMode[childID], now: now) {
                endPrompt(readings: readings, now: now)
            }
            timers
            sickCard(readings: readings, clear: clear, now: now)
            medicineSection(medicines, clear: clear, now: now)
            todaySection(now: now)
            timelineSection(readings: readings, medicines: medicines, now: now)
            endButton
        }
    }

    // MARK: End prompt

    /// Board j7: a day with no fever and no dose asks to go back to the usual Home.
    private func endPrompt(readings: [SickMode.Reading], now: Date) -> some View {
        var facts: [String] = []
        if let newest = readings.first {
            facts.append(String(localized: "Last reading \(unit.format(newest.value)) \(SickMode.when(newest.time, at: true, now: now))."))
        }
        if let dose = doses.first {
            facts.append(String(localized: "Last dose \(SickMode.when(dose.timestamp, at: true, now: now))."))
        }
        return BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BBColor.success.opacity(scheme == .dark ? 0.22 : 0.15))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(BBColor.success)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No fever for 24 hours").font(.headline)
                        if !facts.isEmpty {
                            Text(facts.joined(separator: " ")).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    Button("End sick mode") { onEnd(.endPrompt) }.buttonStyle(.bbPrimary)
                    Button("Keep it on", action: onKeepOn).buttonStyle(.bbNeutral)
                }
                Text(Self.endCaption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: BBRadius.card, style: .continuous)
                .strokeBorder(BBColor.success, lineWidth: 1.5)
        }
        .onAppear { sickMode.countEndPrompt(childID) }
    }

    static var endCaption: String { String(localized: "Every reading and dose stays in Baby Buddy. Home goes back to its usual layout.") }

    // MARK: Sick card

    private func sickCard(readings: [SickMode.Reading], clear: Bool, now: Date) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RunningDot(color: BBColor.danger).accessibilityHidden(true)
                    Text("Sick mode · day \(SickMode.day(since: startedAt, now: now))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BBColor.danger)
                }
                if let newest = readings.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.format(newest.value))
                            .font(BBFont.timer)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(footnote(readings, clear: clear, now: now))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("No temperature logged yet").font(.footnote).foregroundStyle(.secondary)
                }
                if !clear {
                    let window = readings.prefix { now.timeIntervalSince($0.time) <= 86_400 }
                    if !window.isEmpty {
                        SickTemperatureChart(
                            readings: window.reversed(),
                            lead: readings.dropFirst(window.count).first,
                            doses: doses.filter { now.timeIntervalSince($0.timestamp) <= 86_400 && $0.timestamp <= now }
                                .map { ($0.timestamp, colors.color($0.payloadObject["name"] as? String ?? "").color) },
                            unit: unit, line: line, now: now)
                    }
                    Button(action: onLogTemperature) {
                        Label { Text("Log temperature") } icon: { EntityKind.temperature.icon(17) }
                    }
                    .buttonStyle(.bbPrimary)
                }
            }
        }
    }

    /// "2:10 PM · down 1.1° since 11:00 AM" against the highest reading in the six hours before;
    /// once clear, "2:05 PM · under 100.4° since yesterday 1:50 PM".
    private func footnote(_ readings: [SickMode.Reading], clear: Bool, now: Date) -> String {
        guard let newest = readings.first else { return "" }
        var parts = [SickMode.when(newest.time, now: now)]
        if clear {
            if let under = SickMode.underSince(readings, line: line) {
                parts.append(String(localized: "under \(TemperatureUnit.decimal(line))° since \(SickMode.when(under.time, now: now))"))
            }
        } else if let trend = SickMode.trend(readings), trend.change != 0 {
            parts.append(String(localized: "\(trend.change < 0 ? String(localized: "down") : String(localized: "up")) \(TemperatureUnit.decimal(abs(trend.change)))° since \(SickMode.when(trend.since.time, now: now))"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Medicine

    private func medicineSection(_ medicines: [SickMode.Medicine], clear: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(String(localized: "Medicine"))
                if !clear {
                    Text(remindersOn ? String(localized: "Reminders on") : String(localized: "Reminders off"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(medicines, id: \.dose.localID) { medicine in
                if clear { compactRow(medicine, now: now) } else { medicineCard(medicine, now: now) }
            }
            if medicines.isEmpty {
                Text("No doses since sick mode started.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func medicineCard(_ medicine: SickMode.Medicine, now: Date) -> some View {
        let color = colors.color(medicine.name).color
        let okSince: Date? = if case .okNow(let since) = medicine.phase { since } else { nil }
        return BBCard(cornerRadius: BBRadius.row, padding: 14) {
            VStack(alignment: .leading, spacing: okSince == nil ? 12 : 14) {
                HStack(spacing: 12) {
                    ActivityTile(kind: .medication, size: 40, glyph: 21, color: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medicine.name).font(.headline)
                        Text(details(medicine, now: now)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    switch medicine.phase {
                    case .okNow:
                        Text("OK now")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BBColor.successAccent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(BBColor.success.opacity(scheme == .dark ? 0.22 : 0.15),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .waiting(let next, _):
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(timerInterval: now...next, countsDown: true)
                                .font(.headline).monospacedDigit()
                            Text("until \(SickMode.when(next, now: now))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    case .noInterval:
                        EmptyView()
                    }
                }
                .accessibilityElement(children: .combine)
                switch medicine.phase {
                case .okNow:
                    Button { onLogDose(medicine.dose) } label: {
                        Text([String(localized: "Log \(medicine.name.lowercased())"), EntityFormatting.dosage(medicine.dose)]
                            .compactMap { $0 }.joined(separator: " · "))
                    }
                    // Dark on tint: `success` brightens in dark mode, where white stops reading.
                    .buttonStyle(BBFilledButton(background: BBColor.success,
                                                foreground: .adaptive(light: "FFFFFF", dark: "0C0E12")))
                case .waiting(_, let progress):
                    Capsule().fill(BBColor.controlFill).frame(height: 8)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(color).frame(width: geo.size.width * min(max(progress, 0), 1))
                            }
                        }
                        .accessibilityHidden(true)
                case .noInterval:
                    EmptyView()
                }
                Text([Self.doseCount(medicine.recentDoses),
                      okSince.map { String(localized: "OK since \(SickMode.when($0, now: now))") }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if okSince != nil {
                RoundedRectangle(cornerRadius: BBRadius.row, style: .continuous)
                    .strokeBorder(BBColor.success, lineWidth: 2)
            }
        }
    }

    /// "5 mL · last 9:15 AM · every 6 hr".
    private func details(_ medicine: SickMode.Medicine, now: Date) -> String {
        let interval = (medicine.dose.payloadObject["next_dose_interval"] as? String).flatMap(APIDuration.parse)
        return [EntityFormatting.dosage(medicine.dose),
                String(localized: "last \(SickMode.when(medicine.dose.timestamp, now: now))"),
                interval.flatMap { $0 > 0 ? String(localized: "every \(SickMode.duration($0))") : nil }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func doseCount(_ count: Int) -> String {
        String(localized: "\(count) doses in the last 24 hours")
    }

    /// Once clear, a medicine is only a reminder of when it was last given.
    private func compactRow(_ medicine: SickMode.Medicine, now: Date) -> some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            HStack(spacing: 12) {
                ActivityTile(kind: .medication, size: 40, glyph: 21, color: colors.color(medicine.name).color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(medicine.name).font(.subheadline.weight(.semibold))
                    Text("last \(SickMode.when(medicine.dose.timestamp, now: now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Not needed").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Today

    private func todaySection(now: Date) -> some View {
        let today = entities.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }
        let fluids = today.filter { $0.kind == .feeding }
            .compactMap { $0.payloadObject["amount"] as? Double }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 9) {
            SectionHeader(String(localized: "Today"))
            LazyVGrid(columns: columns, spacing: 9) {
                tile(.temperature, String(localized: "Highest"), SickMode.highestText(today, unit: unit))
                tile(.medication, String(localized: "Doses"), "\(today.filter { $0.kind == .medication }.count)")
                tile(.change, String(localized: "Wet diapers"),
                     "\(today.filter { $0.kind == .change && $0.payloadObject["wet"] as? Bool == true }.count)")
                tile(.feeding, String(localized: "Fluids"), fluids > 0 ? EntityFormatting.formatAmount(fluids) : "—")
            }
        }
    }

    /// A Today tile pushes that kind's day, as on the usual Home.
    private func tile(_ kind: EntityKind, _ label: String, _ value: String) -> some View {
        NavigationLink(value: kind) { MetricTile(kind: kind, label: label, value: value) }
            .buttonStyle(.plain)
    }

    // MARK: Timeline

    /// A row on the sick timeline: something due, a record, or a medicine that has come due.
    private struct Item: Identifiable {
        enum Mark { case due, done, okay }
        let id: String
        let time: Date
        let title: String
        var detail: String?
        var value: String?
        let color: Color
        let mark: Mark
        var entity: LocalEntity?
    }

    @ViewBuilder
    private func timelineSection(readings: [SickMode.Reading], medicines: [SickMode.Medicine], now: Date) -> some View {
        let items = timelineItems(readings: readings, medicines: medicines, now: now)
        let rows = items.due + items.past
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(String(localized: "Timeline"))
                    Button("See all", action: onSeeAll)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BBColor.brandAccent)
                }
                BBCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(items.due) { item in
                            row(item, first: item.id == rows.first?.id, last: item.id == rows.last?.id)
                        }
                        nowRow
                        ForEach(items.past) { item in
                            let view = row(item, first: item.id == rows.first?.id, last: item.id == rows.last?.id)
                            if let entity = item.entity {
                                Button { onEdit(entity) } label: { view }.buttonStyle(.plain)
                            } else {
                                view
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
    }

    /// What's due, latest first, above "Now"; then today's records and the medicines that came due
    /// since their last dose, newest first, up to eight.
    private func timelineItems(readings: [SickMode.Reading], medicines: [SickMode.Medicine],
                               now: Date) -> (due: [Item], past: [Item]) {
        let calendar = Calendar.current
        var due: [Item] = []
        var past: [Item] = []
        for medicine in medicines {
            let color = colors.color(medicine.name).color
            switch medicine.phase {
            case .waiting(let next, _):
                due.append(Item(id: "due-\(medicine.dose.localID)", time: next, title: String(localized: "\(medicine.name) OK"),
                                detail: String(localized: "in \(SickMode.duration(next.timeIntervalSince(now)))")
                                    + (remindersOn ? " · reminder set" : ""),
                                color: color, mark: .due))
            case .okNow(let since) where calendar.isDate(since, inSameDayAs: now):
                past.append(Item(id: "ok-\(medicine.dose.localID)", time: since, title: String(localized: "\(medicine.name) OK"),
                                 detail: String(localized: "Not given yet"), color: color, mark: .okay))
            default:
                break
            }
        }
        if checkHours > 0, let newest = readings.first, SickMode.isFever(newest.value, line: line) {
            let check = newest.time.addingTimeInterval(Double(checkHours) * 3600)
            if check > now {
                due.append(Item(id: "check", time: check, title: String(localized: "Temperature check"),
                                detail: String(localized: "Reminder · every \(checkHours) hr while fever"),
                                color: BBColor.brand, mark: .due))
            }
        }
        for entity in entities where entity.kind != .timer && entity.kind != .child
            && entity.timestamp <= now && calendar.isDate(entity.timestamp, inSameDayAs: now) {
            past.append(record(entity))
        }
        return (due.sorted { $0.time > $1.time },
                Array(past.sorted { $0.time > $1.time }.prefix(8)))
    }

    private func record(_ entity: LocalEntity) -> Item {
        let id = entity.localID.uuidString
        switch entity.kind {
        case .medication:
            let name = (entity.payloadObject["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            return Item(id: id, time: entity.timestamp, title: name.isEmpty ? String(localized: "Medication") : name,
                        value: EntityFormatting.dosage(entity), color: colors.color(name).color,
                        mark: .done, entity: entity)
        case .temperature:
            let value = SickMode.readings([entity], unit: unit).first.map { TemperatureUnit.decimal($0.value) + "°" }
            return Item(id: id, time: entity.timestamp, title: entity.kind.displayName, value: value,
                        color: BBColor.activity(.temperature), mark: .done, entity: entity)
        default:
            let subtitle = EntityFormatting.subtitle(entity)
            return Item(id: id, time: entity.timestamp, title: entity.kind.displayName,
                        detail: subtitle?.isEmpty == false ? subtitle : nil,
                        color: BBColor.activity(entity.kind), mark: .done, entity: entity)
        }
    }

    private func row(_ item: Item, first: Bool, last: Bool) -> some View {
        let due = item.mark == .due
        return HStack(alignment: .top, spacing: 12) {
            Text(item.time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: due ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(due ? BBColor.brandAccent : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 14)
            dot(item).frame(width: 20).padding(.top, 14)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: due ? .medium : .semibold))
                        .foregroundStyle(due ? Color.primary.opacity(0.8) : Color.primary)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value = item.value {
                    Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
            }
            .padding(.vertical, 12)
        }
        // The rail: joins the dots, and stops at the first and the last.
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle().fill(first ? Color.clear : BBColor.railLine).frame(height: 14)
                Color.clear.frame(height: 14)
                Rectangle().fill(last ? Color.clear : BBColor.railLine)
            }
            .frame(width: 2)
            .padding(.leading, 58 + 12 + 9)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func dot(_ item: Item) -> some View {
        switch item.mark {
        case .due:
            Circle().strokeBorder(item.color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                .frame(width: 14, height: 14)
        case .done:
            Circle().fill(item.color).frame(width: 14, height: 14)
        case .okay:
            Circle().fill(BBColor.card).overlay(Circle().strokeBorder(item.color, lineWidth: 2.5))
                .frame(width: 14, height: 14)
        }
    }

    private var nowRow: some View {
        HStack(spacing: 12) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58)
                .padding(.vertical, 3)
                .background(BBColor.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Rectangle().fill(BBColor.primary).frame(height: 2)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now")
    }

    // MARK: End

    private var endButton: some View {
        VStack(spacing: 8) {
            Button("End sick mode") { onEnd(.home) }.buttonStyle(.bbNeutral)
            Text(Self.endCaption)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Fever banner

/// Board j1: on the usual Home, a reading over the fever line offers sick mode. Closing it, or "Not
/// now", dismisses it for that reading only.
struct FeverBanner: View {
    let reading: SickMode.Reading
    let unit: TemperatureUnit
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ActivityTile(kind: .temperature, size: 40, glyph: 21)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(unit.format(reading.value)) is over the fever line").font(.headline)
                        Text("Logged \(SickMode.when(reading.time, at: true)). Sick mode keeps temperatures, doses and diapers on one screen.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(BBColor.controlFill, in: Circle())
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-8) // a 44pt target around the 28pt circle
                    .accessibilityLabel("Dismiss")
                }
                HStack(spacing: 8) {
                    Button("Start sick mode", action: onStart).buttonStyle(.bbPrimary)
                    Button("Not now", action: onDismiss).buttonStyle(.bbNeutral)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: BBRadius.card, style: .continuous)
                .strokeBorder(BBColor.brand, lineWidth: 1.5)
        }
    }
}

// MARK: - Chart

/// The sick card's day of temperatures: the readings as a line over a faint fill, the fever line
/// dashed across, a capsule along the bottom for each dose in its medicine's color, and a ring on
/// the newest reading. Drawn with paths rather than Charts, because it has no axes and the dose
/// band sits below the plot.
struct SickTemperatureChart: View {
    /// Oldest first, in `unit`, from the last 24 hours.
    let readings: [SickMode.Reading]
    /// The reading before those, so the line comes in from the left edge rather than starting mid-air.
    let lead: SickMode.Reading?
    let doses: [(time: Date, color: Color)]
    let unit: TemperatureUnit
    let line: Double
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let values = readings.map(\.value) + [line]
            let low = values.min()!, high = values.max()!
            let span = max(high - low, unit == .fahrenheit ? 2 : 1.1)
            let bottom = low - span * 0.25, top = high + span * 0.15
            let x = { (date: Date) in 4 + CGFloat(1 - now.timeIntervalSince(date) / 86_400) * (geo.size.width - 12) }
            let y = { (value: Double) in 6 + CGFloat((top - min(max(value, bottom), top)) / (top - bottom)) * 52 }
            let points = ([lead].compactMap { $0 } + readings).map { CGPoint(x: x($0.time), y: y($0.value)) }
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y(line)))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y(line)))
                }
                .stroke(BBColor.danger.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if points.count > 1 {
                    Path { path in
                        path.addLines(points)
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: 62))
                        path.addLine(to: CGPoint(x: points[0].x, y: 62))
                        path.closeSubpath()
                    }
                    .fill(BBColor.brand.opacity(0.12))
                    Path { path in path.addLines(points) }
                        .stroke(BBColor.brand, style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                }
                ForEach(doses.indices, id: \.self) { index in
                    Capsule().fill(doses[index].color)
                        .frame(width: 5, height: 9)
                        .position(x: x(doses[index].time), y: 68.5)
                }
                if let last = points.last {
                    Circle().fill(BBColor.card)
                        .overlay(Circle().stroke(BBColor.brand, lineWidth: 2.25))
                        .frame(width: 9, height: 9)
                        .position(last)
                }
            }
        }
        .frame(height: 74)
        .clipped() // the lead reading sits off the left edge
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// "Temperature over the last 24 hours, peaking at 102.8°F at 3:30 AM. Latest 100.8°F."
    private var summary: String {
        guard let peak = readings.max(by: { $0.value < $1.value }), let latest = readings.last else { return "" }
        return String(localized: "Temperature over the last 24 hours, peaking at \(unit.format(peak.value)) \(SickMode.when(peak.time, at: true, now: now)). Latest \(unit.format(latest.value)).")
    }
}
