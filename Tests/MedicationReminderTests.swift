import XCTest
import SwiftData
@testable import BabyBuddy

@MainActor
final class MedicationReminderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let time = ISO8601DateFormatter().date(from: "2026-06-15T02:00:00Z")!

    override func setUp() async throws {
        container = LocalStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func dose(_ name: String, child: Int = 1, at offset: TimeInterval = 0, every interval: String?) -> LocalEntity {
        var payload: [String: Any] = [
            "child": child, "name": name, "time": APIDate.isoDateTime.string(from: time.addingTimeInterval(offset)),
        ]
        payload["next_dose_interval"] = interval ?? NSNull()
        return LocalRepository(context: context).create(kind: .medication, payload: payload)!
    }

    func testDurationParsesServerStrings() {
        XCTAssertEqual(APIDuration.parse("04:00:00"), 14_400)
        XCTAssertEqual(APIDuration.parse("1 06:30:00"), 109_800)
        XCTAssertEqual(APIDuration.parse("00:00:01.500000"), 1.5)
        XCTAssertNil(APIDuration.parse("4h"))
        XCTAssertNil(APIDuration.parse(""))
    }

    func testOnlyWritableStringMedicationFieldsAdvertiseCustomUnits() async throws {
        let session = StubProtocol.install([
            #"{"actions":{"POST":{"dosage_unit":{"type":"choice","read_only":false}}}}"#,
            #"{"actions":{"POST":{"dosage_unit":{"type":"string","read_only":true,"max_length":20}}}}"#,
            #"{"actions":{"POST":{"dosage_unit":{"type":"string","read_only":false,"max_length":20}}}}"#,
        ])
        let client = APIClient(config: ServerConfig(baseURL: URL(string: "https://example.test")!,
                                                   token: "fixture"), session: session)
        let fixed = try await client.customMedicationUnitLimit()
        let readOnly = try await client.customMedicationUnitLimit()
        let custom = try await client.customMedicationUnitLimit()
        XCTAssertNil(fixed)
        XCTAssertNil(readOnly)
        XCTAssertEqual(custom, 20)
        XCTAssertEqual(StubProtocol.requests.map(\.httpMethod), Array(repeating: "OPTIONS", count: 3))
        XCTAssertEqual(StubProtocol.requestedURLs.map(\.absoluteString),
                       Array(repeating: "https://example.test/api/medication/", count: 3))
    }

    func testDurationFormatsLikeTheServer() {
        XCTAssertEqual(APIDuration.string(from: 5400), "01:30:00")
        XCTAssertEqual(APIDuration.string(from: 86_400), "1 00:00:00")
        for seconds in MedicationReminderPolicy.choices + [15_600] {
            XCTAssertEqual(APIDuration.parse(APIDuration.string(from: seconds)), seconds)
        }
    }

    func testNextDoseIsTimePlusInterval() {
        XCTAssertEqual(MedicationReminderPolicy.nextDose(after: dose("Tylenol", every: "04:00:00")),
                       time.addingTimeInterval(14_400))
        XCTAssertNil(MedicationReminderPolicy.nextDose(after: dose("Tylenol", every: nil)))
        XCTAssertNil(MedicationReminderPolicy.nextDose(after: dose("Tylenol", every: "00:00:00")))
    }

    func testLatestDoseSupersedesEarlierOnesPerChildAndName() {
        let early = dose("Tylenol", every: "04:00:00")
        let late = dose("tylenol ", at: 3600, every: nil)
        let other = dose("Motrin", every: "06:00:00")
        let sibling = dose("Tylenol", child: 2, every: "04:00:00")
        let latest = MedicationReminderPolicy.latestDoses([early, late, other, sibling]).map(\.localID)
        XCTAssertEqual(Set(latest), [late.localID, other.localID, sibling.localID])
    }

    func testRequestNamesMedicationChildAndLastDose() {
        let tylenol = dose("Tylenol", every: "04:00:00")
        let request = MedicationReminderPolicy.request(for: tylenol, childName: "Maya")!
        XCTAssertEqual(request.id, "medication-\(tylenol.localID.uuidString)")
        XCTAssertEqual(request.fireDate, time.addingTimeInterval(14_400))
        XCTAssertEqual(request.title, "Tylenol: next dose OK")
        XCTAssertEqual(request.body,
                       "4h since Maya's last dose at \(time.formatted(date: .omitted, time: .shortened)).")
        XCTAssertEqual(request.url, "babybuddy://dose/\(tylenol.localID.uuidString)")
        XCTAssertNil(MedicationReminderPolicy.request(for: dose("Motrin", every: nil), childName: nil))
    }

    func testWarnsOnlyWhileTheNewestDoseIsNotYetOK() {
        let doses = [dose("Tylenol", every: "06:00:00"), dose("Tylenol", at: 3600, every: "06:00:00")]
        let wait = MedicationReminderPolicy.doseNotYetOK(named: " tylenol", childID: 1, in: doses,
                                                         now: time.addingTimeInterval(4 * 3600))
        XCTAssertEqual(wait?.dose.localID, doses[1].localID)
        XCTAssertEqual(wait?.next, time.addingTimeInterval(7 * 3600))
        XCTAssertNil(MedicationReminderPolicy.doseNotYetOK(named: "Tylenol", childID: 1, in: doses,
                                                           now: time.addingTimeInterval(7 * 3600)))
        XCTAssertNil(MedicationReminderPolicy.doseNotYetOK(named: "Tylenol", childID: 2, in: doses, now: time))
        XCTAssertNil(MedicationReminderPolicy.doseNotYetOK(named: "", childID: 1, in: doses, now: time))
    }

    func testPlanSkipsOverdueDosesAndLeavesTimersAlone() {
        let due = MedicationReminderPolicy.request(for: dose("Tylenol", every: "04:00:00"), childName: nil)!
        let past = MedicationReminderPolicy.request(for: dose("Motrin", at: -86_400, every: "06:00:00"), childName: nil)!
        let plan = ForgottenTimerPolicy.plan(
            wanted: [due, past],
            pending: ["medication-deleted": time, "timer-running": time],
            delivered: [], now: time, prefix: "medication-", firesOverdue: false)
        XCTAssertEqual(plan.add, [due])                  // an old dose never fires late
        XCTAssertEqual(plan.remove, ["medication-deleted"]) // the timer's request isn't ours to drop
    }

    func testPlanReschedulesAnEditedDose() {
        let request = MedicationReminderPolicy.request(for: dose("Tylenol", every: "08:00:00"), childName: nil)!
        let plan = ForgottenTimerPolicy.plan(
            wanted: [request], pending: [request.id: time.addingTimeInterval(14_400)], delivered: [],
            now: time, prefix: "medication-", firesOverdue: false)
        XCTAssertEqual(plan.add, [request])
    }
}
