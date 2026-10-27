import SwiftUI
import SwiftData

/// Settings ▸ Sick mode ▸ Fever line: 37.5 to 38.5 °C, shown in the phone's unit. The line is
/// stored in Celsius, so changing the unit changes how it reads, not where it sits.
struct FeverLineView: View {
    @AppStorage(SickMode.feverLineKey, store: SharedDefaults.suite) private var feverLine = SickMode.defaultFeverLine
    private let unit = TemperatureUnit.current

    var body: some View {
        ChoiceList(
            title: String(localized: "Fever line"), options: SickMode.feverLineChoices,
            selection: Binding(get: { feverLine }, set: { celsius in
                feverLine = celsius
                Task { await LocalAlerts.shared.reconcile() } // a check follows only a fever
            }),
            label: { unit.format(unit.convert($0, from: .celsius)) },
            footer: String(localized: "A reading at or over this line counts as a fever. It brings up the banner on Home and keeps temperature checks coming."))
    }
}

/// Settings ▸ Sick mode ▸ Temperature checks: how long after a reading over the line to remind.
struct TemperatureChecksView: View {
    @AppStorage(SickMode.checkHoursKey, store: SharedDefaults.suite) private var hours = SickMode.defaultCheckHours

    static func label(_ hours: Int) -> String { hours == 0 ? String(localized: "Off") : String(localized: "Every \(hours) hr") }

    var body: some View {
        ChoiceList(
            title: String(localized: "Temperature checks"), options: SickMode.checkHourChoices,
            selection: Binding(get: { hours }, set: { new in
                hours = new
                // Like the notification switches: turning it on asks for permission.
                Task {
                    if new > 0 { _ = await LocalAlerts.shared.requestAuthorization() }
                    await LocalAlerts.shared.reconcile()
                }
            }),
            label: Self.label,
            footer: String(localized: "While sick mode is on and the newest reading is over the fever line, a reminder comes this long after it."))
    }
}

/// A pushed list of choices with a check on the selected one.
private struct ChoiceList<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let footer: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element) { index, option in
                            if index > 0 { Rectangle().fill(BBColor.divider).frame(height: 0.5) }
                            Button { selection = option } label: {
                                HStack {
                                    Text(label(option)).font(.system(size: 16))
                                    Spacer()
                                    if option == selection {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(BBColor.brandAccent)
                                    }
                                }
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(option == selection ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 15)
                }
                Text(footer)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
        .background(BBColor.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Medicine colors

/// Settings ▸ Sick mode ▸ Medicine colors (board j5): each medicine's color and where it came from,
/// with swatches to change it on this phone. A pick other than the server's color asks first.
struct MedicineColorsView: View {
    @State private var store = MedicineColorStore.shared
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "medication" },
           sort: \LocalEntity.timestamp, order: .reverse)
    private var doses: [LocalEntity]
    @State private var expanded: String?
    /// A pick that differs from the server's color, waiting on the warning.
    @State private var pending: Pick?

    struct Pick: Identifiable {
        let name: String
        let color: MedicineColor
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(String(localized: "Medicines"))
                    BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(medicines, id: \.self) { name in
                                medicineRow(name)
                                if expanded == name { swatches(name) }
                                Rectangle().fill(BBColor.divider).frame(height: 0.5)
                            }
                            nextRow
                        }
                        .padding(.horizontal, 15)
                    }
                    Text("Each medicine gets the next color in the order it first appears on your server, so every phone shows the same colors. A color you change here changes on this phone only.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.top, 2)
                }
                Button("Reset to server colors") { store.resetOverrides() }
                    .buttonStyle(.bbTinted)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
        .background(BBColor.surface)
        .navigationTitle("Medicine colors")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $pending) { pick in
            MedicineColorWarning(name: pick.name, server: store.serverColor(pick.name), picked: pick.color,
                                 onCancel: { present(nil) },
                                 onUse: { store.set(pick.color, for: pick.name); present(nil) })
                .presentationBackground(.clear)
        }
    }

    /// Every medicine with a color, in server order, named as it was last logged.
    private var medicines: [String] {
        var names: [String: String] = [:]
        for dose in doses {
            let name = (dose.payloadObject["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let key = MedicationReminderPolicy.normalizedName(name)
            if names[key] == nil { names[key] = name }
        }
        return store.assigned.map { names[$0] ?? $0.capitalized }
    }

    /// What a medicine shows: the pick waiting on the warning, else its color.
    private func shown(_ name: String) -> MedicineColor {
        pending.flatMap { $0.name == name ? $0.color : nil } ?? store.color(name)
    }

    private func medicineRow(_ name: String) -> some View {
        let color = store.color(name)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { expanded = expanded == name ? nil : name }
        } label: {
            SettingsRow(symbol: "pills.fill", tint: shown(name).color, title: name,
                        subtitle: String(localized: "\(color.name) · \(store.isOverridden(name) ? String(localized: "this phone only") : String(localized: "from your server"))")) {
                Image(systemName: expanded == name ? "chevron.up" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded == name ? String(localized: "Hides the colors") : String(localized: "Shows the colors"))
    }

    private func swatches(_ name: String) -> some View {
        let selected = shown(name)
        return HStack(spacing: 0) {
            ForEach(MedicineColor.allCases) { color in
                Button { pick(color, for: name) } label: {
                    ZStack {
                        if color == selected { Circle().strokeBorder(color.color, lineWidth: 2.5) }
                        Circle().fill(color.color).frame(width: 32, height: 32)
                        if color == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(color == selected ? .isSelected : [])
                if color != MedicineColor.allCases.last { Spacer(minLength: 0) }
            }
        }
        .padding(.bottom, 14)
    }

    /// The row that says what the next medicine to appear will get.
    private var nextRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(store.next.color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 30, height: 30)
            Text("Next new medicine").font(.system(size: 16)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(store.next.name).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    /// The server's own color applies at once; any other asks first.
    private func pick(_ color: MedicineColor, for name: String) {
        guard color != store.color(name) else { return }
        if color == store.serverColor(name) {
            store.set(color, for: name)
        } else {
            present(Pick(name: name, color: color))
        }
    }

    /// Presented without the cover's slide-up. The warning springs in by itself, as an alert does.
    private func present(_ pick: Pick?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pending = pick }
    }
}

/// Board j6: a color other than the server's changes on this phone only. A centred card in a clear
/// cover, like ``SignOutDialog``, because `confirmationDialog` loses its Cancel on iOS 26.
struct MedicineColorWarning: View {
    let name: String
    let server: MedicineColor
    let picked: MedicineColor
    let onCancel: () -> Void
    let onUse: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.55 : 0.42)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
            card
                .padding(.horizontal, 30)
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { shown = true } }
    }

    private var card: some View {
        BBCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(picked.color.opacity(scheme == .dark ? 0.22 : 0.15))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "paintbrush.pointed.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(picked.color)
                        }
                    Text("Only on this phone").font(.system(size: 21, weight: .semibold))
                }
                HStack(spacing: 10) {
                    Circle().fill(server.color).frame(width: 14, height: 14)
                    Text(name).lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Circle().fill(picked.color).frame(width: 14, height: 14)
                    Text(picked.name)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(BBColor.nested, in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name): \(server.name) to \(picked.name)")
                Text("Your server gave \(name.lowercased()) \(server.name.lowercased()), and other phones keep showing it that way. To match, change it on each phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel).buttonStyle(.bbNeutral)
                    Button("Use \(picked.name.lowercased())", action: onUse).buttonStyle(.bbPrimary)
                }
                .padding(.top, 2)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
        // `.contain` first: a label on a plain container is stamped onto every child.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Color changes only on this phone")
    }
}
