import SwiftUI
import UniformTypeIdentifiers

struct SubReminder: Identifiable, Hashable {
    let id: UUID
    var minute: Int
    var outPlayerID: UUID
    var inPlayerID: UUID
    var triggered: Bool
}

struct SubLogEntry: Identifiable, Hashable {
    let id: UUID
    var time: Int
    var outPlayerID: UUID
    var inPlayerID: UUID
    var outName: String
    var inName: String
    var note: String
}

enum GamePlayerStatus: String, CaseIterable, Identifiable {
    case available = "Available"
    case late = "Late"
    case injured = "Injured"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .available: return .green
        case .late: return .orange
        case .injured: return .red
        }
    }
}

struct GameDayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var starterIDs: Set<UUID> = []
    @State private var playingSeconds: [UUID: Int] = [:]
    @State private var elapsedSeconds = 0
    @State private var periodStartSeconds = 0
    @State private var currentPeriod = 1
    @State private var isRunning = false
    @State private var reminders: [SubReminder] = []
    @State private var subLog: [SubLogEntry] = []
    @State private var playerStatuses: [UUID: GamePlayerStatus] = [:]
    @State private var newReminderMinute = 15
    @State private var selectedOutPlayerID: UUID?
    @State private var selectedInPlayerID: UUID?
    @State private var activeReminder: SubReminder?
    @State private var showReminder = false
    @State private var formation: LineupFormation = .balanced

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GameClockPanel(
                    elapsedSeconds: elapsedSeconds,
                    periodSeconds: periodSeconds,
                    currentPeriod: currentPeriod,
                    targetMinutes: store.selectedTeam.ageGroup.defaultGameMinutes,
                    isRunning: isRunning,
                    starters: availableStarterPlayers.count,
                    playersOnField: store.selectedTeam.ageGroup.playersOnField,
                    startAction: { isRunning = true },
                    pauseAction: { isRunning = false },
                    resetAction: resetGameClock,
                    nextPeriodAction: advancePeriod,
                    resetPeriodAction: resetPeriodClock
                )

                quickSubSection
                lineupSection
                reminderSection
                playingTimeSection

                if !subLog.isEmpty {
                    subLogSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: resetLineup)
        .onChange(of: store.selectedTeamID) { _ in
            resetLineup()
        }
        .onReceive(ticker) { _ in
            tick()
        }
        .alert("Substitution Reminder", isPresented: $showReminder) {
            Button("Record Sub") {
                if let activeReminder {
                    applySubstitution(activeReminder)
                }
                activeReminder = nil
            }
            Button("Keep Lineup", role: .cancel) {
                activeReminder = nil
            }
        } message: {
            Text(activeReminderText)
        }
    }

    private var starterPlayers: [Player] {
        store.roster.filter { starterIDs.contains($0.id) }
    }

    private var availableStarterPlayers: [Player] {
        starterPlayers.filter { status(for: $0) == .available }
    }

    private var benchPlayers: [Player] {
        store.roster.filter { !starterIDs.contains($0.id) }
    }

    private var availableBenchPlayers: [Player] {
        benchPlayers.filter { status(for: $0) == .available }
    }

    private var periodSeconds: Int {
        max(0, elapsedSeconds - periodStartSeconds)
    }

    private var activeReminderText: String {
        guard let reminder = activeReminder else { return "" }
        let outName = playerName(reminder.outPlayerID)
        let inName = playerName(reminder.inPlayerID)
        return "\(formatClock(reminder.minute * 60)): put \(inName) in for \(outName)."
    }

    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lineup")

            HStack {
                Label("\(store.selectedTeam.ageGroup.rawValue): \(store.selectedTeam.ageGroup.playersOnField)v\(store.selectedTeam.ageGroup.playersOnField)", systemImage: "shield")
                Spacer()
                Text("\(availableStarterPlayers.count) / \(store.selectedTeam.ageGroup.playersOnField) available starters")
                    .foregroundStyle(availableStarterPlayers.count == store.selectedTeam.ageGroup.playersOnField ? Color.secondary : Color.orange)
            }
            .font(.subheadline)

            Picker("Formation", selection: $formation) {
                ForEach(LineupFormation.allCases) { formation in
                    Text(formation.rawValue).tag(formation)
                }
            }
            .pickerStyle(.segmented)

            LineupPitchView(
                players: starterPlayers,
                formation: formation,
                playersOnField: store.selectedTeam.ageGroup.playersOnField,
                playingSeconds: playingSeconds,
                statuses: playerStatuses,
                dropAction: { providers in
                    handlePlayerDrop(providers, target: .starters)
                },
                slotDropAction: { playerID, providers in
                    handlePlayerDrop(providers, target: .starterSlot(playerID))
                }
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                LineupColumn(
                    title: "Starting Team",
                    symbol: "figure.soccer",
                    players: starterPlayers,
                    playingSeconds: playingSeconds,
                    statuses: playerStatuses,
                    actionTitle: "Bench",
                    actionSymbol: "arrow.down.circle",
                    action: moveToBench,
                    statusAction: setPlayerStatus,
                    dropAction: { providers in
                        handlePlayerDrop(providers, target: .starters)
                    },
                    playerDropAction: { player, providers in
                        handlePlayerDrop(providers, target: .starterSlot(player.id))
                    }
                )

                LineupColumn(
                    title: "Bench",
                    symbol: "person.2",
                    players: benchPlayers,
                    playingSeconds: playingSeconds,
                    statuses: playerStatuses,
                    actionTitle: "Start",
                    actionSymbol: "arrow.up.circle",
                    action: moveToStarter,
                    statusAction: setPlayerStatus,
                    dropAction: { providers in
                        handlePlayerDrop(providers, target: .bench)
                    },
                    playerDropAction: { _, providers in
                        handlePlayerDrop(providers, target: .bench)
                    }
                )
            }
        }
    }

    private var quickSubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Quick Sub")

            VStack(alignment: .leading, spacing: 12) {
                Picker("Sub Out", selection: outSelectionBinding) {
                    Text("Choose starter").tag(UUID?.none)
                    ForEach(availableStarterPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Picker("Sub In", selection: inSelectionBinding) {
                    Text("Choose bench").tag(UUID?.none)
                    ForEach(availableBenchPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                HStack {
                    Button {
                        recordSelectedSub()
                    } label: {
                        Label("Record Sub", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedOutPlayerID == nil || selectedInPlayerID == nil)

                    Button {
                        undoLastSub()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canUndoLastSub)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Sub Reminders")

            VStack(alignment: .leading, spacing: 12) {
                Stepper("Minute \(newReminderMinute)", value: $newReminderMinute, in: 1...store.selectedTeam.ageGroup.defaultGameMinutes)

                Picker("Sub Out", selection: outSelectionBinding) {
                    Text("Choose player").tag(UUID?.none)
                    ForEach(availableStarterPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Picker("Sub In", selection: inSelectionBinding) {
                    Text("Choose player").tag(UUID?.none)
                    ForEach(availableBenchPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Button {
                    addReminder()
                } label: {
                    Label("Add Reminder", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOutPlayerID == nil || selectedInPlayerID == nil)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if reminders.isEmpty {
                Text("No reminders set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(reminders.sorted { $0.minute < $1.minute }) { reminder in
                        ReminderRow(reminder: reminder, outName: playerName(reminder.outPlayerID), inName: playerName(reminder.inPlayerID)) {
                            applySubstitution(reminder)
                        } deleteAction: {
                            reminders.removeAll { $0.id == reminder.id }
                        }
                    }
                }
            }
        }
    }

    private var playingTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Playing Time")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(store.roster) { player in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("#\(player.number)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(status: status(for: player), isStarter: starterIDs.contains(player.id))
                        }
                        Text(player.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(formatClock(playingSeconds[player.id, default: 0]))
                            .font(.title3.monospacedDigit().weight(.bold))
                        Menu {
                            ForEach(GamePlayerStatus.allCases) { status in
                                Button(status.rawValue) {
                                    setPlayerStatus(player, status)
                                }
                            }
                        } label: {
                            Label(status(for: player).rawValue, systemImage: "person.crop.circle.badge.questionmark")
                                .font(.caption)
                                .foregroundStyle(status(for: player).color)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var subLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Sub Log")

            ForEach(subLog) { entry in
                HStack {
                    Text(formatClock(entry.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.inName) in for \(entry.outName)")
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .font(.subheadline)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var outSelectionBinding: Binding<UUID?> {
        Binding {
            selectedOutPlayerID
        } set: { value in
            selectedOutPlayerID = value
        }
    }

    private var inSelectionBinding: Binding<UUID?> {
        Binding {
            selectedInPlayerID
        } set: { value in
            selectedInPlayerID = value
        }
    }

    private func tick() {
        guard isRunning else { return }

        elapsedSeconds += 1
        for playerID in starterIDs where playerStatuses[playerID, default: .available] == .available {
            playingSeconds[playerID, default: 0] += 1
        }

        if let index = reminders.firstIndex(where: { !$0.triggered && elapsedSeconds >= $0.minute * 60 }) {
            reminders[index].triggered = true
            activeReminder = reminders[index]
            showReminder = true
        }
    }

    private func resetLineup() {
        isRunning = false
        elapsedSeconds = 0
        reminders.removeAll()
        subLog.removeAll()
        playerStatuses = Dictionary(uniqueKeysWithValues: store.roster.map { ($0.id, GamePlayerStatus.available) })
        playingSeconds = Dictionary(uniqueKeysWithValues: store.roster.map { ($0.id, 0) })
        starterIDs = Set(store.roster.prefix(store.selectedTeam.ageGroup.playersOnField).map(\.id))
        periodStartSeconds = 0
        currentPeriod = 1
        normalizeSelections()
    }

    private func resetGameClock() {
        isRunning = false
        elapsedSeconds = 0
        periodStartSeconds = 0
        currentPeriod = 1
        playingSeconds = Dictionary(uniqueKeysWithValues: store.roster.map { ($0.id, 0) })
        reminders = reminders.map { reminder in
            var updated = reminder
            updated.triggered = false
            return updated
        }
        subLog.removeAll()
    }

    private func advancePeriod() {
        isRunning = false
        currentPeriod += 1
        periodStartSeconds = elapsedSeconds
    }

    private func resetPeriodClock() {
        isRunning = false
        elapsedSeconds = periodStartSeconds
        reminders = reminders.map { reminder in
            var updated = reminder
            updated.triggered = elapsedSeconds >= reminder.minute * 60
            return updated
        }
    }

    private func moveToBench(_ player: Player) {
        starterIDs.remove(player.id)
        normalizeSelections()
    }

    private func moveToStarter(_ player: Player) {
        guard starterIDs.count < store.selectedTeam.ageGroup.playersOnField else { return }
        guard status(for: player) == .available else { return }
        starterIDs.insert(player.id)
        normalizeSelections()
    }

    private func addReminder() {
        guard let outID = selectedOutPlayerID, let inID = selectedInPlayerID else { return }
        reminders.append(SubReminder(id: UUID(), minute: newReminderMinute, outPlayerID: outID, inPlayerID: inID, triggered: false))
    }

    private func applySubstitution(_ reminder: SubReminder) {
        substitute(outID: reminder.outPlayerID, inID: reminder.inPlayerID, note: "Reminder")
        reminders.removeAll { $0.id == reminder.id }
    }

    private func recordSelectedSub() {
        guard let outID = selectedOutPlayerID, let inID = selectedInPlayerID else { return }
        substitute(outID: outID, inID: inID, note: "Manual sub")
    }

    private func substitute(outID: UUID, inID: UUID, note: String) {
        guard starterIDs.contains(outID), !starterIDs.contains(inID) else { return }
        guard playerStatuses[outID, default: .available] == .available, playerStatuses[inID, default: .available] == .available else { return }
        starterIDs.remove(outID)
        starterIDs.insert(inID)
        subLog.insert(
            SubLogEntry(id: UUID(), time: elapsedSeconds, outPlayerID: outID, inPlayerID: inID, outName: playerName(outID), inName: playerName(inID), note: note),
            at: 0
        )
        normalizeSelections()
    }

    private func handlePlayerDrop(_ providers: [NSItemProvider], target: LineupDropTarget) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? NSString, let playerID = UUID(uuidString: value as String) else { return }

            DispatchQueue.main.async {
                moveDroppedPlayer(playerID, target: target)
            }
        }

        return true
    }

    private func moveDroppedPlayer(_ playerID: UUID, target: LineupDropTarget) {
        guard let player = store.roster.first(where: { $0.id == playerID }) else { return }

        switch target {
        case .bench:
            moveToBench(player)
        case .starters:
            guard status(for: player) == .available else { return }

            if starterIDs.contains(player.id) {
                return
            }

            if starterIDs.count < store.selectedTeam.ageGroup.playersOnField {
                moveToStarter(player)
            } else if let outPlayer = availableStarterPlayers.first {
                substitute(outID: outPlayer.id, inID: player.id, note: "Drag swap")
            }
        case .starterSlot(let outPlayerID):
            guard player.id != outPlayerID, status(for: player) == .available else { return }

            if starterIDs.contains(player.id), starterIDs.contains(outPlayerID) {
                return
            } else if starterIDs.contains(outPlayerID) {
                substitute(outID: outPlayerID, inID: player.id, note: "Drag swap")
            } else if starterIDs.count < store.selectedTeam.ageGroup.playersOnField {
                moveToStarter(player)
            }
        }
    }

    private var canUndoLastSub: Bool {
        guard let last = subLog.first else { return false }
        return starterIDs.contains(last.inPlayerID) && !starterIDs.contains(last.outPlayerID)
    }

    private func undoLastSub() {
        guard canUndoLastSub, let last = subLog.first else { return }
        starterIDs.remove(last.inPlayerID)
        starterIDs.insert(last.outPlayerID)
        subLog.removeFirst()
        normalizeSelections()
    }

    private func setPlayerStatus(_ player: Player, _ status: GamePlayerStatus) {
        playerStatuses[player.id] = status

        if status != .available {
            starterIDs.remove(player.id)
        } else if starterIDs.count < store.selectedTeam.ageGroup.playersOnField && starterIDs.isEmpty {
            starterIDs.insert(player.id)
        }

        normalizeSelections()
    }

    private func normalizeSelections() {
        if selectedOutPlayerID == nil || !availableStarterPlayers.contains(where: { $0.id == selectedOutPlayerID }) {
            selectedOutPlayerID = availableStarterPlayers.first?.id
        }

        if selectedInPlayerID == nil || !availableBenchPlayers.contains(where: { $0.id == selectedInPlayerID }) {
            selectedInPlayerID = availableBenchPlayers.first?.id
        }
    }

    private func status(for player: Player) -> GamePlayerStatus {
        playerStatuses[player.id, default: .available]
    }

    private func playerName(_ id: UUID) -> String {
        store.roster.first { $0.id == id }?.name ?? "Player"
    }
}

enum LineupDropTarget {
    case starters
    case starterSlot(UUID)
    case bench
}

enum LineupFormation: String, CaseIterable, Identifiable {
    case balanced = "Balanced"
    case defensive = "Defensive"
    case attacking = "Attacking"

    var id: String { rawValue }

    func slots(for playersOnField: Int) -> [LineupSlot] {
        switch playersOnField {
        case 4:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 1, midfielders: 1, forwards: 1)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 1, forwards: 0)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 1, midfielders: 0, forwards: 2)
            }
        case 7:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 3, forwards: 1)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 2, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 2, midfielders: 2, forwards: 2)
            }
        case 9:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 3, forwards: 2)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 4, midfielders: 3, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 2, forwards: 3)
            }
        default:
            switch self {
            case .balanced:
                return slots(goalkeeper: 1, defenders: 4, midfielders: 3, forwards: 3)
            case .defensive:
                return slots(goalkeeper: 1, defenders: 5, midfielders: 4, forwards: 1)
            case .attacking:
                return slots(goalkeeper: 1, defenders: 3, midfielders: 4, forwards: 3)
            }
        }
    }

    private func slots(goalkeeper: Int, defenders: Int, midfielders: Int, forwards: Int) -> [LineupSlot] {
        var result: [LineupSlot] = []
        result.append(contentsOf: rowSlots(count: goalkeeper, y: 0.88, label: "GK"))
        result.append(contentsOf: rowSlots(count: defenders, y: 0.68, label: "DEF"))
        result.append(contentsOf: rowSlots(count: midfielders, y: 0.46, label: "MID"))
        result.append(contentsOf: rowSlots(count: forwards, y: 0.22, label: "FWD"))
        return result
    }

    private func rowSlots(count: Int, y: CGFloat, label: String) -> [LineupSlot] {
        guard count > 0 else { return [] }

        let horizontalInset: CGFloat = count == 1 ? 0.5 : 0.18
        let step = count == 1 ? 0 : (1 - horizontalInset * 2) / CGFloat(count - 1)

        return (0..<count).map { index in
            let x = count == 1 ? 0.5 : horizontalInset + CGFloat(index) * step
            return LineupSlot(label: slotLabel(label, index: index, count: count), position: CGPoint(x: x, y: y))
        }
    }

    private func slotLabel(_ label: String, index: Int, count: Int) -> String {
        guard count > 1 else { return label }

        switch index {
        case 0:
            return "L \(label)"
        case count - 1:
            return "R \(label)"
        default:
            return label
        }
    }
}

struct LineupSlot: Identifiable {
    let id = UUID()
    let label: String
    let position: CGPoint
}

struct GameClockPanel: View {
    let elapsedSeconds: Int
    let periodSeconds: Int
    let currentPeriod: Int
    let targetMinutes: Int
    let isRunning: Bool
    let starters: Int
    let playersOnField: Int
    let startAction: () -> Void
    let pauseAction: () -> Void
    let resetAction: () -> Void
    let nextPeriodAction: () -> Void
    let resetPeriodAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatClock(elapsedSeconds))
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Period \(currentPeriod) - \(formatClock(periodSeconds)) this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(starters)/\(playersOnField)")
                        .font(.title2.weight(.bold))
                    Text("on field")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(elapsedSeconds), total: Double(max(targetMinutes * 60, 1)))

            HStack {
                Label("Target \(targetMinutes) min", systemImage: "flag.checkered")
                Spacer()
                Button {
                    resetPeriodAction()
                } label: {
                    Label("Reset Period", systemImage: "timer")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    isRunning ? pauseAction() : startAction()
                } label: {
                    Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    nextPeriodAction()
                } label: {
                    Label(currentPeriod == 1 ? "Halftime" : "Next Period", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    resetAction()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LineupColumn: View {
    let title: String
    let symbol: String
    let players: [Player]
    let playingSeconds: [UUID: Int]
    let statuses: [UUID: GamePlayerStatus]
    let actionTitle: String
    let actionSymbol: String
    let action: (Player) -> Void
    let statusAction: (Player, GamePlayerStatus) -> Void
    let dropAction: ([NSItemProvider]) -> Bool
    let playerDropAction: (Player, [NSItemProvider]) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)

            if players.isEmpty {
                Text("No players")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(players) { player in
                    HStack(spacing: 10) {
                        PlayerAvatar(number: player.number, position: player.position)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(formatClock(playingSeconds[player.id, default: 0]))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusBadge(status: statuses[player.id, default: .available], isStarter: title == "Starting Team")

                        Menu {
                            ForEach(GamePlayerStatus.allCases) { status in
                                Button(status.rawValue) {
                                    statusAction(player, status)
                                }
                            }
                        } label: {
                            Label("Status", systemImage: "person.crop.circle.badge.questionmark")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            action(player)
                        } label: {
                            Label(actionTitle, systemImage: actionSymbol)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onDrag {
                        NSItemProvider(object: player.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        playerDropAction(player, providers)
                    }
                }
            }
        }
        .padding(1)
        .onDrop(of: [UTType.plainText], isTargeted: nil, perform: dropAction)
    }
}

struct LineupPitchView: View {
    let players: [Player]
    let formation: LineupFormation
    let playersOnField: Int
    let playingSeconds: [UUID: Int]
    let statuses: [UUID: GamePlayerStatus]
    let dropAction: ([NSItemProvider]) -> Bool
    let slotDropAction: (UUID, [NSItemProvider]) -> Bool

    private var slots: [LineupSlot] {
        formation.slots(for: playersOnField)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let visibleSlots = Array(slots.prefix(playersOnField))
            let assignments = Array(zip(players, visibleSlots))

            ZStack {
                SoccerPitch()

                ForEach(visibleSlots.dropFirst(players.count)) { slot in
                    EmptyLineupSlot(slot: slot)
                        .position(x: slot.position.x * size.width, y: slot.position.y * size.height)
                }

                ForEach(assignments, id: \.0.id) { player, slot in
                    LineupPitchMarker(
                        player: player,
                        slot: slot,
                        playingSeconds: playingSeconds[player.id, default: 0],
                        status: statuses[player.id, default: .available]
                    )
                    .position(x: slot.position.x * size.width, y: slot.position.y * size.height)
                    .onDrag {
                        NSItemProvider(object: player.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        slotDropAction(player.id, providers)
                    }
                }
            }
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label("\(formation.rawValue) Shape", systemImage: "square.grid.3x3")
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(10)
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil, perform: dropAction)
    }
}

struct LineupPitchMarker: View {
    let player: Player
    let slot: LineupSlot
    let playingSeconds: Int
    let status: GamePlayerStatus

    var body: some View {
        VStack(spacing: 3) {
            Text(slot.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("#\(player.number)")
                .font(.caption.weight(.bold))
            Text(player.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(formatClock(playingSeconds))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 82, height: 62)
        .padding(4)
        .background(status == .available ? Color(.systemBackground).opacity(0.95) : status.color.opacity(0.86))
        .foregroundStyle(status == .available ? Color.primary : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }
}

struct EmptyLineupSlot: View {
    let slot: LineupSlot

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.caption.weight(.bold))
            Text(slot.label)
                .font(.caption2.weight(.bold))
        }
        .frame(width: 64, height: 48)
        .background(Color.white.opacity(0.22))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

struct StatusBadge: View {
    let status: GamePlayerStatus
    let isStarter: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status == .available && !isStarter ? Color.gray.opacity(0.45) : status.color)
                .frame(width: 8, height: 8)
            Text(status == .available && isStarter ? "On" : status.rawValue)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background((status == .available ? Color.green : status.color).opacity(0.12))
        .foregroundStyle(status == .available && !isStarter ? Color.secondary : status.color)
        .clipShape(Capsule())
    }
}

struct ReminderRow: View {
    let reminder: SubReminder
    let outName: String
    let inName: String
    let applyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(formatClock(reminder.minute * 60))
                .font(.headline.monospacedDigit())
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(inName) for \(outName)")
                    .font(.subheadline.weight(.semibold))
                Text(reminder.triggered ? "Reminder sent" : "Pending")
                    .font(.caption)
                    .foregroundStyle(reminder.triggered ? .orange : .secondary)
            }

            Spacer()

            Button {
                applyAction()
            } label: {
                Label("Record", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                deleteAction()
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

func formatClock(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", remainingSeconds))"
}
