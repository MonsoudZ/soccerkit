import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewTeam = false
    @State private var showingEditTeam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TeamHeader(team: store.selectedTeam)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Players", value: "\(store.roster.count)", symbol: "person.3.fill")
                    MetricTile(title: "Sessions", value: "\(store.teamSessions.count)", symbol: "calendar")
                    MetricTile(title: "Games", value: "\(store.teamGames.count)", symbol: "soccerball")
                    MetricTile(title: "Drills", value: "\(store.teamDrills.count)", symbol: "sportscourt.fill")
                }

                if let game = store.nextGame {
                    SectionHeader("Next Game")
                    GameSummaryCard(game: game)
                }

                if let session = store.nextSession {
                    SectionHeader("Next Training")
                    SessionSummaryCard(session: session)
                }

                SectionHeader("Roster Snapshot")
                VStack(spacing: 10) {
                    ForEach(store.roster.prefix(5)) { player in
                        PlayerRow(player: player)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            Button {
                showingEditTeam = true
            } label: {
                Label("Edit Team", systemImage: "slider.horizontal.3")
            }

            Button {
                showingNewTeam = true
            } label: {
                Label("New Team", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewTeam) {
            NavigationStack {
                TeamFormView()
            }
        }
        .sheet(isPresented: $showingEditTeam) {
            NavigationStack {
                TeamFormView(team: store.selectedTeam)
            }
        }
    }
}

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddPlayer = false

    var body: some View {
        List {
            Section("Team Rules") {
                Picker("Age Group", selection: ageGroupBinding) {
                    ForEach(AgeGroup.allCases) { ageGroup in
                        Text(ageGroup.rawValue).tag(ageGroup)
                    }
                }

                LabeledContent("Roster Limit", value: "\(store.roster.count) / \(store.selectedTeam.ageGroup.maxRosterSize)")
                LabeledContent("Game Format", value: "\(store.selectedTeam.ageGroup.playersOnField)v\(store.selectedTeam.ageGroup.playersOnField)")

                if store.roster.count > store.selectedTeam.ageGroup.maxRosterSize {
                    Label("Roster is over the selected age group's max.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(store.roster) { player in
                    NavigationLink {
                        PlayerDetailView(playerID: player.id)
                    } label: {
                        PlayerRow(player: player)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deletePlayer(player)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(store.selectedTeam.ageGroup.rawValue) Roster")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            Button {
                showingAddPlayer = true
            } label: {
                Label("Add Player", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            NavigationStack {
                PlayerFormView()
            }
        }
    }

    private var ageGroupBinding: Binding<AgeGroup> {
        Binding {
            store.selectedTeam.ageGroup
        } set: { newValue in
            store.setAgeGroup(newValue, for: store.selectedTeam)
        }
    }
}

struct PlayerDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let playerID: UUID
    @State private var showingEditPlayer = false

    private var player: Player? {
        store.players.first { $0.id == playerID }
    }

    var body: some View {
        Group {
            if let player {
                Form {
                    Section("Player") {
                        LabeledContent("Name", value: player.name)
                        LabeledContent("Number", value: "#\(player.number)")
                        LabeledContent("Position", value: player.position.rawValue)
                    }

                    Section("Parent / Guardian") {
                        LabeledContent("Guardian", value: player.guardian.isEmpty ? "—" : player.guardian)
                        ContactRow(label: "Phone", value: player.guardianPhone, kind: .phone)
                        ContactRow(label: "Email", value: player.guardianEmail, kind: .email)
                    }

                    if !player.secondaryContactName.isEmpty || !player.secondaryContactPhone.isEmpty {
                        Section("Secondary Contact") {
                            if !player.secondaryContactName.isEmpty {
                                LabeledContent("Name", value: player.secondaryContactName)
                            }
                            ContactRow(label: "Phone", value: player.secondaryContactPhone, kind: .phone)
                        }
                    }

                    Section("Emergency Contact") {
                        if player.emergencyContactName.isEmpty && player.emergencyContactPhone.isEmpty {
                            Text("No emergency contact on file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if !player.emergencyContactName.isEmpty {
                                LabeledContent("Name", value: player.emergencyContactName)
                            }
                            ContactRow(label: "Phone", value: player.emergencyContactPhone, kind: .phone)
                            if !player.emergencyContactRelation.isEmpty {
                                LabeledContent("Relationship", value: player.emergencyContactRelation)
                            }
                        }
                    }

                    Section("Medical") {
                        if player.allergies.isEmpty && player.medicalNotes.isEmpty {
                            Text("No medical notes on file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if !player.allergies.isEmpty {
                                LabeledContent("Allergies") {
                                    Text(player.allergies)
                                        .foregroundStyle(.red)
                                }
                            }
                            if !player.medicalNotes.isEmpty {
                                Text(player.medicalNotes)
                            }
                        }
                    }

                    Section("Coach Notes") {
                        Text(player.notes.isEmpty ? "—" : player.notes)
                    }
                }
            } else {
                EmptyStateView(title: "Player Removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(player?.name ?? "Player")
        .toolbar {
            if let player {
                Button {
                    showingEditPlayer = true
                } label: {
                    Label("Edit Player", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deletePlayer(player)
                    dismiss()
                } label: {
                    Label("Delete Player", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditPlayer) {
            if let player {
                NavigationStack {
                    PlayerFormView(player: player)
                }
            }
        }
    }
}

struct TrainingPlannerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewSession = false

    var body: some View {
        List {
            ForEach(store.teamSessions) { session in
                NavigationLink {
                    SessionDetailView(sessionID: session.id)
                } label: {
                    SessionSummaryCard(session: session)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.deleteSession(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            Button {
                showingNewSession = true
            } label: {
                Label("New Session", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewSession) {
            NavigationStack {
                SessionFormView()
            }
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    @State private var showingEditSession = false

    private var session: TrainingSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                List {
                    Section("Session") {
                        LabeledContent("Team", value: store.teamName(for: session.teamID))
                        LabeledContent("Weather", value: session.weather)
                        LabeledContent("Time", value: session.date.formatted(date: .omitted, time: .shortened))
                        LabeledContent("Total Time", value: "\(session.blocks.reduce(0) { $0 + $1.minutes }) min")
                    }

                    Section("Description") {
                        Text(session.objective)
                            .font(.body)
                    }

                    Section("Plan") {
                        if session.blocks.isEmpty {
                            Text("No drills planned yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.blocks) { block in
                                if let drill = store.drill(for: block.drillID) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("\(block.minutes) min", systemImage: "timer")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Label("\(block.intensity) / 5", systemImage: "flame")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(drill.category.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.thinMaterial)
                                                .clipShape(Capsule())
                                        }

                                        Text(block.topic.isEmpty ? drill.title : block.topic)
                                            .font(.headline)

                                        Text(drill.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if !block.pitchArea.isEmpty {
                                            Label(block.pitchArea, systemImage: "rectangle.dashed")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if !block.positions.isEmpty {
                                            Text("Positions: \(block.positions.map(\.rawValue).joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(block.focus)
                                            .foregroundStyle(.secondary)

                                        if !block.details.isEmpty {
                                            Text(block.details)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let diagram = store.diagram(for: block.diagramID) {
                                            NavigationLink {
                                                DiagramPreviewView(diagramID: diagram.id)
                                            } label: {
                                                Label(diagram.title, systemImage: "sportscourt")
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    Section("Field Diagrams") {
                        let diagrams = store.diagrams(for: session)
                        if diagrams.isEmpty {
                            Text("No diagrams attached.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(diagrams) { diagram in
                                NavigationLink {
                                    DiagramPreviewView(diagramID: diagram.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(diagram.title)
                                            .font(.headline)
                                        Text("Updated \(diagram.updatedAt, style: .date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: session.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: session)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(session.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }

                    Section("Attendance") {
                        ForEach(store.roster) { player in
                            AttendanceRow(player: player, session: session)
                        }
                    }
                }
            } else {
                EmptyStateView(title: "Session Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(session?.title ?? "Session")
        .toolbar {
            if let session {
                Button {
                    showingEditSession = true
                } label: {
                    Label("Edit Session", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deleteSession(session)
                    dismiss()
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditSession) {
            if let session {
                NavigationStack {
                    SessionFormView(session: session)
                }
            }
        }
    }
}

struct GamesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewGame = false

    var body: some View {
        List {
            if store.teamGames.isEmpty {
                Text("No games scheduled yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.teamGames) { game in
                    NavigationLink {
                        GameDetailView(gameID: game.id)
                    } label: {
                        GameSummaryCard(game: game)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteGame(game)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            Button {
                showingNewGame = true
            } label: {
                Label("New Game", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewGame) {
            NavigationStack {
                GameFormView()
            }
        }
    }
}

struct GameDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let gameID: UUID
    @State private var showingEditGame = false

    private var game: GameEvent? {
        store.games.first { $0.id == gameID }
    }

    var body: some View {
        Group {
            if let game {
                List {
                    Section("Game") {
                        LabeledContent("Opponent", value: game.opponent)
                        LabeledContent("Venue", value: game.isHome ? "Home" : "Away")
                        LabeledContent("Date", value: game.date.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Time", value: game.date.formatted(date: .omitted, time: .shortened))
                        if !game.location.isEmpty {
                            LabeledContent("Location", value: game.location)
                        }
                    }

                    if !game.notes.isEmpty {
                        Section("Notes") {
                            Text(game.notes)
                        }
                    }

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: game.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: game)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(game.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }
                }
            } else {
                EmptyStateView(title: "Game Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(game.map { "vs \($0.opponent)" } ?? "Game")
        .toolbar {
            if let game {
                Button {
                    showingEditGame = true
                } label: {
                    Label("Edit Game", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deleteGame(game)
                    dismiss()
                } label: {
                    Label("Delete Game", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditGame) {
            if let game {
                NavigationStack {
                    GameFormView(game: game)
                }
            }
        }
    }
}

struct GameSummaryCard: View {
    @EnvironmentObject private var store: AppStore
    let game: GameEvent

    var body: some View {
        let summary = store.rsvpSummary(game.rsvps)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs \(game.opponent)")
                        .font(.headline)
                    Text(game.date, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(game.isHome ? "Home" : "Away")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }

            if !game.location.isEmpty {
                Label(game.location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(summary.going) going", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(summary.maybe) maybe", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Label("\(summary.notGoing) out", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DiagramPreviewView: View {
    @EnvironmentObject private var store: AppStore
    let diagramID: UUID

    private var diagram: TacticsDiagram? {
        store.diagrams.first { $0.id == diagramID }
    }

    var body: some View {
        Group {
            if let diagram {
                ScrollView {
                    DiagramExportView(diagram: diagram)
                        .padding()
                }
                .background(Color(.systemGroupedBackground))
            } else {
                EmptyStateView(title: "Diagram Removed", systemImage: "rectangle.dashed")
            }
        }
        .navigationTitle(diagram?.title ?? "Diagram")
    }
}

struct AttendanceRow: View {
    @EnvironmentObject private var store: AppStore
    let player: Player
    let session: TrainingSession

    var status: AttendanceStatus {
        session.attendance[player.id] ?? .absent
    }

    var body: some View {
        HStack {
            PlayerAvatar(number: player.number, position: player.position)

            VStack(alignment: .leading) {
                Text(player.name)
                    .font(.headline)
                Text(player.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(AttendanceStatus.allCases) { option in
                    Button(option.rawValue) {
                        store.setAttendance(option, for: player, in: session)
                    }
                }
            } label: {
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.16))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
    }

    var statusColor: Color {
        switch status {
        case .present: return .green
        case .late: return .orange
        case .excused: return .blue
        case .absent: return .red
        }
    }
}

struct DrillLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var category: DrillCategory?
    @State private var scope: DrillLibraryScope = .team
    @State private var selectedTag: String?
    @State private var showingNewDrill = false

    var filteredDrills: [Drill] {
        visibleDrills
            .filter { drill in
                category == nil || drill.category == category
            }
            .filter { drill in
                guard let selectedTag else { return true }
                return drill.tags.contains(selectedTag)
            }
    }

    var visibleDrills: [Drill] {
        switch scope {
        case .team:
            return store.teamDrills
        case .shared:
            return store.drills.filter { $0.teamID == nil }.sorted { $0.title < $1.title }
        case .all:
            return store.drills.sorted { $0.title < $1.title }
        }
    }

    var visibleTags: [String] {
        Array(Set(visibleDrills.flatMap(\.tags))).sorted()
    }

    var body: some View {
        List {
            Section {
                Picker("Library", selection: $scope) {
                    ForEach(DrillLibraryScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Category", selection: $category) {
                    Text("All").tag(DrillCategory?.none)
                    ForEach(DrillCategory.allCases) { item in
                        Text(item.rawValue).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)

                if !visibleTags.isEmpty {
                    Picker("Tag", selection: tagBinding) {
                        Text("All Tags").tag(String?.none)
                        ForEach(visibleTags, id: \.self) { tag in
                            Text(tag).tag(Optional(tag))
                        }
                    }
                }
            }

            if filteredDrills.isEmpty {
                Text("No drills match these filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredDrills) { drill in
                    NavigationLink {
                        DrillDetailView(drillID: drill.id)
                    } label: {
                        DrillCard(drill: drill)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteDrill(drill)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .onChange(of: scope) { _ in
            if let selectedTag, !visibleTags.contains(selectedTag) {
                self.selectedTag = nil
            }
        }
        .onChange(of: selectedTag) { tag in
            if let tag, !visibleTags.contains(tag) {
                selectedTag = nil
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Drills")
        .toolbar {
            Button {
                showingNewDrill = true
            } label: {
                Label("Add Drill", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewDrill) {
            NavigationStack {
                DrillFormView()
            }
        }
    }

    private var tagBinding: Binding<String?> {
        Binding {
            selectedTag
        } set: { value in
            selectedTag = value
        }
    }
}

enum DrillLibraryScope: String, CaseIterable, Identifiable {
    case team = "Team"
    case shared = "Shared"
    case all = "All"

    var id: String { rawValue }
}

struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.14))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct DrillDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let drillID: UUID
    @State private var showingEditDrill = false

    private var drill: Drill? {
        store.drills.first { $0.id == drillID }
    }

    var body: some View {
        Group {
            if let drill {
                Form {
                    Section("Drill") {
                        LabeledContent("Library", value: store.teamName(for: drill.teamID))
                        LabeledContent("Category", value: drill.category.rawValue)
                        LabeledContent("Duration", value: "\(drill.durationMinutes) min")
                        if !drill.fieldSize.isEmpty {
                            LabeledContent("Field Size", value: drill.fieldSize)
                        }
                        if !drill.tags.isEmpty {
                            TagChipsView(tags: drill.tags)
                        }
                    }

                    Section("Setup") {
                        Text(drill.fieldSetup)
                    }

                    Section("Field Diagrams") {
                        let diagrams = store.diagrams(for: drill)
                        if diagrams.isEmpty {
                            Text("No diagrams attached to this drill.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(diagrams) { diagram in
                                NavigationLink {
                                    DiagramPreviewView(diagramID: diagram.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(diagram.title)
                                            .font(.headline)
                                        Text("Updated \(diagram.updatedAt, style: .date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    DrillDetailListSection(title: "Equipment Needed", items: drill.equipment, symbol: "cone")

                    Section("Coaching Points") {
                        ForEach(drill.coachingPoints, id: \.self) { point in
                            Label(point, systemImage: "checkmark.circle")
                        }
                    }

                    DrillDetailListSection(title: "Progression", items: drill.progressions, symbol: "arrow.up.forward.circle")
                    DrillDetailListSection(title: "Regression", items: drill.regressions, symbol: "arrow.down.backward.circle")
                }
            } else {
                EmptyStateView(title: "Drill Removed", systemImage: "sportscourt")
            }
        }
        .navigationTitle(drill?.title ?? "Drill")
        .toolbar {
            if let drill {
                Button {
                    showingEditDrill = true
                } label: {
                    Label("Edit Drill", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deleteDrill(drill)
                    dismiss()
                } label: {
                    Label("Delete Drill", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditDrill) {
            if let drill {
                NavigationStack {
                    DrillFormView(drill: drill)
                }
            }
        }
    }
}

struct DrillDetailListSection: View {
    let title: String
    let items: [String]
    let symbol: String

    var body: some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: symbol)
                }
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

struct TeamHeader: View {
    let team: Team

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team.name)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            HStack(spacing: 8) {
                Label(team.ageGroup.rawValue, systemImage: "shield")
                Label(team.season, systemImage: "leaf")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.teal.opacity(0.22), Color.indigo.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.teal)
            Text(value)
                .font(.title.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SessionSummaryCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TrainingSession

    var body: some View {
        let summary = store.attendanceSummary(for: session)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text(session.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(totalMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.objective)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(summary.present), total: Double(max(summary.total, 1)))

            Text("\(summary.present) of \(summary.total) expected players marked present or late")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var totalMinutes: Int {
        session.blocks.reduce(0) { $0 + $1.minutes }
    }
}

struct DrillCard: View {
    @EnvironmentObject private var store: AppStore
    let drill: Drill

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(drill.title)
                    .font(.headline)
                Spacer()
                Label("\(drill.durationMinutes) min", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(drill.category.rawValue)
                Text(store.teamName(for: drill.teamID))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            TagChipsView(tags: drill.tags)

            HStack(spacing: 10) {
                if !drill.fieldSize.isEmpty {
                    Label(drill.fieldSize, systemImage: "rectangle.dashed")
                }
                if !drill.equipment.isEmpty {
                    Label("\(drill.equipment.count) equipment", systemImage: "cone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(drill.fieldSetup)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(drill.coachingPoints, id: \.self) { point in
                    Label(point, systemImage: "checkmark.circle")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

enum ContactKind {
    case phone
    case email

    func url(for value: String) -> URL? {
        switch self {
        case .phone:
            let digits = value.filter { !$0.isWhitespace }
            return URL(string: "tel:\(digits)")
        case .email:
            return URL(string: "mailto:\(value)")
        }
    }
}

struct ContactRow: View {
    let label: String
    let value: String
    let kind: ContactKind

    var body: some View {
        LabeledContent(label) {
            if value.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else if let url = kind.url(for: value) {
                Link(value, destination: url)
            } else {
                Text(value)
            }
        }
    }
}

struct RSVPRow: View {
    let player: Player
    let status: RSVPStatus
    let setStatus: (RSVPStatus) -> Void

    var body: some View {
        HStack {
            PlayerAvatar(number: player.number, position: player.position)

            VStack(alignment: .leading) {
                Text(player.name)
                    .font(.headline)
                Text(player.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(RSVPStatus.allCases) { option in
                    Button(option.rawValue) {
                        setStatus(option)
                    }
                }
            } label: {
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.16))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
            }
        }
    }
}

extension RSVPStatus {
    var color: Color {
        switch self {
        case .going: return .green
        case .maybe: return .orange
        case .notGoing: return .red
        case .noResponse: return .secondary
        }
    }
}

struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(number: player.number, position: player.position)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.headline)
                Text("\(player.position.rawValue) - Guardian: \(player.guardian)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlayerAvatar: View {
    let number: Int
    let position: PlayerPosition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
            Text("#\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }

    var color: Color {
        switch position {
        case .goalkeeper: return .orange
        case .defender: return .blue
        case .midfielder: return .teal
        case .forward: return .red
        }
    }
}

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}
