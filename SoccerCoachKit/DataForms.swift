import SwiftUI

struct TeamFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let team: Team?
    @State private var name: String
    @State private var ageGroup: AgeGroup
    @State private var season: String
    @State private var accentName: String
    @State private var defaultPlayerCount: Int
    @State private var defaultOpponentCount: Int
    @State private var defaultConeCount: Int
    @State private var defaultZoneCount: Int

    init(team: Team? = nil) {
        self.team = team
        _name = State(initialValue: team?.name ?? "")
        _ageGroup = State(initialValue: team?.ageGroup ?? .u12)
        _season = State(initialValue: team?.season ?? "Fall 2026")
        _accentName = State(initialValue: team?.accentName ?? "Teal")
        _defaultPlayerCount = State(initialValue: team?.trainingDefaults.playerCount ?? TrainingBoardDefaults.standard.playerCount)
        _defaultOpponentCount = State(initialValue: team?.trainingDefaults.opponentCount ?? TrainingBoardDefaults.standard.opponentCount)
        _defaultConeCount = State(initialValue: team?.trainingDefaults.coneCount ?? TrainingBoardDefaults.standard.coneCount)
        _defaultZoneCount = State(initialValue: team?.trainingDefaults.zoneCount ?? TrainingBoardDefaults.standard.zoneCount)
    }

    var body: some View {
        Form {
            Section("Team") {
                TextField("Team name", text: $name)
                Picker("Age Group", selection: $ageGroup) {
                    ForEach(AgeGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                TextField("Season", text: $season)
                TextField("Accent", text: $accentName)
            }

            Section("Rules") {
                LabeledContent("Roster Limit", value: "\(ageGroup.maxRosterSize)")
                LabeledContent("Game Format", value: "\(ageGroup.playersOnField)v\(ageGroup.playersOnField)")
                LabeledContent("Default Game", value: "\(ageGroup.defaultGameMinutes) min")
            }

            Section("Training Board Defaults") {
                Stepper("Players \(defaultPlayerCount)", value: $defaultPlayerCount, in: 0...22)
                Stepper("Opposition \(defaultOpponentCount)", value: $defaultOpponentCount, in: 0...22)
                Stepper("Cones \(defaultConeCount)", value: $defaultConeCount, in: 0...40)
                Stepper("Zones \(defaultZoneCount)", value: $defaultZoneCount, in: 0...8)
            }
        }
        .navigationTitle(team == nil ? "New Team" : "Edit Team")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeason = season.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccent = accentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = TrainingBoardDefaults(
            playerCount: defaultPlayerCount,
            opponentCount: defaultOpponentCount,
            coneCount: defaultConeCount,
            zoneCount: defaultZoneCount
        )

        if let team {
            store.updateTeam(
                Team(
                    id: team.id,
                    name: cleanName,
                    ageGroup: ageGroup,
                    season: cleanSeason,
                    accentName: cleanAccent.isEmpty ? team.accentName : cleanAccent,
                    trainingDefaults: defaults
                )
            )
        } else {
            store.addTeam(name: cleanName, ageGroup: ageGroup, season: cleanSeason.isEmpty ? "Current Season" : cleanSeason)
            var newTeam = store.selectedTeam
            newTeam.trainingDefaults = defaults
            store.updateTeam(newTeam)
        }
    }
}

struct PlayerFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let player: Player?
    @State private var name: String
    @State private var number: Int
    @State private var position: PlayerPosition
    @State private var guardian: String
    @State private var notes: String
    @State private var guardianPhone: String
    @State private var guardianEmail: String
    @State private var secondaryContactName: String
    @State private var secondaryContactPhone: String
    @State private var emergencyContactName: String
    @State private var emergencyContactPhone: String
    @State private var emergencyContactRelation: String
    @State private var allergies: String
    @State private var medicalNotes: String

    init(player: Player? = nil) {
        self.player = player
        _name = State(initialValue: player?.name ?? "")
        _number = State(initialValue: player?.number ?? 1)
        _position = State(initialValue: player?.position ?? .midfielder)
        _guardian = State(initialValue: player?.guardian ?? "")
        _notes = State(initialValue: player?.notes ?? "")
        _guardianPhone = State(initialValue: player?.guardianPhone ?? "")
        _guardianEmail = State(initialValue: player?.guardianEmail ?? "")
        _secondaryContactName = State(initialValue: player?.secondaryContactName ?? "")
        _secondaryContactPhone = State(initialValue: player?.secondaryContactPhone ?? "")
        _emergencyContactName = State(initialValue: player?.emergencyContactName ?? "")
        _emergencyContactPhone = State(initialValue: player?.emergencyContactPhone ?? "")
        _emergencyContactRelation = State(initialValue: player?.emergencyContactRelation ?? "")
        _allergies = State(initialValue: player?.allergies ?? "")
        _medicalNotes = State(initialValue: player?.medicalNotes ?? "")
    }

    var body: some View {
        Form {
            Section("Player") {
                TextField("Name", text: $name)
                Stepper("Number \(number)", value: $number, in: 0...99)
                Picker("Position", selection: $position) {
                    ForEach(PlayerPosition.allCases) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
            }

            Section("Parent / Guardian") {
                TextField("Guardian name", text: $guardian)
                TextField("Phone", text: $guardianPhone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $guardianEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section("Secondary Contact") {
                TextField("Name", text: $secondaryContactName)
                TextField("Phone", text: $secondaryContactPhone)
                    .keyboardType(.phonePad)
            }

            Section("Emergency Contact") {
                TextField("Name", text: $emergencyContactName)
                TextField("Phone", text: $emergencyContactPhone)
                    .keyboardType(.phonePad)
                TextField("Relationship", text: $emergencyContactRelation)
            }

            Section {
                TextField("Allergies", text: $allergies, axis: .vertical)
                    .lineLimit(1...3)
                TextEditor(text: $medicalNotes)
                    .frame(minHeight: 80)
            } header: {
                Text("Medical")
            } footer: {
                Text("Note allergies, conditions, medications, or anything staff should know in an emergency.")
            }

            Section("Coach Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle(player == nil ? "Add Player" : "Edit Player")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGuardian = guardian.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = Player(
            id: player?.id ?? UUID(),
            teamID: player?.teamID ?? store.selectedTeamID,
            name: cleanName,
            number: number,
            position: position,
            guardian: cleanGuardian,
            notes: notes,
            guardianPhone: trimmed(guardianPhone),
            guardianEmail: trimmed(guardianEmail),
            secondaryContactName: trimmed(secondaryContactName),
            secondaryContactPhone: trimmed(secondaryContactPhone),
            emergencyContactName: trimmed(emergencyContactName),
            emergencyContactPhone: trimmed(emergencyContactPhone),
            emergencyContactRelation: trimmed(emergencyContactRelation),
            allergies: trimmed(allergies),
            medicalNotes: medicalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if player == nil {
            store.players.append(updated)
        } else {
            store.updatePlayer(updated)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GameFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let game: GameEvent?
    @State private var opponent: String
    @State private var date: Date
    @State private var location: String
    @State private var isHome: Bool
    @State private var notes: String

    init(game: GameEvent? = nil) {
        self.game = game
        _opponent = State(initialValue: game?.opponent ?? "")
        _date = State(initialValue: game?.date ?? Date())
        _location = State(initialValue: game?.location ?? "")
        _isHome = State(initialValue: game?.isHome ?? true)
        _notes = State(initialValue: game?.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Game") {
                TextField("Opponent", text: $opponent)
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Picker("Venue", selection: $isHome) {
                    Text("Home").tag(true)
                    Text("Away").tag(false)
                }
                .pickerStyle(.segmented)
                TextField("Location", text: $location)
                LabeledContent("Team", value: store.selectedTeam.name)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(game == nil ? "New Game" : "Edit Game")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let cleanOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        if let game {
            var updated = game
            updated.opponent = cleanOpponent
            updated.date = date
            updated.location = cleanLocation
            updated.isHome = isHome
            updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            store.updateGame(updated)
        } else {
            store.addGame(
                opponent: cleanOpponent,
                date: date,
                location: cleanLocation,
                isHome: isHome,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

struct DrillFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let drill: Drill?
    @State private var title: String
    @State private var teamID: UUID?
    @State private var category: DrillCategory
    @State private var tagsText: String
    @State private var durationMinutes: Int
    @State private var equipmentText: String
    @State private var fieldSize: String
    @State private var fieldSetup: String
    @State private var coachingPointsText: String
    @State private var progressionsText: String
    @State private var regressionsText: String

    init(drill: Drill? = nil) {
        self.drill = drill
        _title = State(initialValue: drill?.title ?? "")
        _teamID = State(initialValue: drill?.teamID)
        _category = State(initialValue: drill?.category ?? .technical)
        _tagsText = State(initialValue: drill?.tags.joined(separator: ", ") ?? "")
        _durationMinutes = State(initialValue: drill?.durationMinutes ?? 15)
        _equipmentText = State(initialValue: drill?.equipment.joined(separator: "\n") ?? "")
        _fieldSize = State(initialValue: drill?.fieldSize ?? "")
        _fieldSetup = State(initialValue: drill?.fieldSetup ?? "")
        _coachingPointsText = State(initialValue: drill?.coachingPoints.joined(separator: "\n") ?? "")
        _progressionsText = State(initialValue: drill?.progressions.joined(separator: "\n") ?? "")
        _regressionsText = State(initialValue: drill?.regressions.joined(separator: "\n") ?? "")
    }

    var body: some View {
        Form {
            Section("Drill") {
                TextField("Title", text: $title)
                Picker("Team", selection: teamBinding) {
                    Text("Shared Library").tag(UUID?.none)
                    ForEach(store.teams) { team in
                        Text(team.name).tag(Optional(team.id))
                    }
                }
                Picker("Category", selection: $category) {
                    ForEach(DrillCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                Stepper("\(durationMinutes) minutes", value: $durationMinutes, in: 1...90)
                TextField("Tags", text: $tagsText)
                    .textInputAutocapitalization(.never)
            }

            Section("Setup") {
                TextField("Field size", text: $fieldSize)
                TextEditor(text: $fieldSetup)
                    .frame(minHeight: 90)
            }

            Section("Equipment Needed") {
                TextEditor(text: $equipmentText)
                    .frame(minHeight: 90)
            }

            Section("Coaching Points") {
                TextEditor(text: $coachingPointsText)
                    .frame(minHeight: 120)
            }

            Section("Progression") {
                TextEditor(text: $progressionsText)
                    .frame(minHeight: 100)
            }

            Section("Regression") {
                TextEditor(text: $regressionsText)
                    .frame(minHeight: 100)
            }
        }
        .onAppear(perform: prepareDefaultTeam)
        .navigationTitle(drill == nil ? "New Drill" : "Edit Drill")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        }
    }

    private var teamBinding: Binding<UUID?> {
        Binding {
            teamID
        } set: { value in
            teamID = value
        }
    }

    private func prepareDefaultTeam() {
        guard drill == nil, teamID == nil else { return }
        teamID = store.selectedTeamID
    }

    private func save() {
        let equipment = lines(from: equipmentText)
        let points = lines(from: coachingPointsText)
        let progressions = lines(from: progressionsText)
        let regressions = lines(from: regressionsText)
        let tags = tagsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .removingDuplicates()

        if let drill {
            store.updateDrill(
                Drill(
                    id: drill.id,
                    teamID: teamID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    tags: tags,
                    durationMinutes: durationMinutes,
                    equipment: equipment,
                    fieldSize: fieldSize.trimmingCharacters(in: .whitespacesAndNewlines),
                    fieldSetup: fieldSetup,
                    coachingPoints: points,
                    progressions: progressions,
                    regressions: regressions
                )
            )
        } else {
            store.addDrill(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                teamID: teamID,
                category: category,
                tags: tags,
                durationMinutes: durationMinutes,
                equipment: equipment,
                fieldSize: fieldSize.trimmingCharacters(in: .whitespacesAndNewlines),
                fieldSetup: fieldSetup,
                coachingPoints: points,
                progressions: progressions,
                regressions: regressions
            )
        }
    }

    private func lines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct SessionFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession?
    @State private var title: String
    @State private var date: Date
    @State private var objective: String
    @State private var weather: String
    @State private var blocks: [TrainingBlock]
    @State private var selectedDrillID: UUID?
    @State private var selectedDiagramID: UUID?
    @State private var newBlockTopic: String
    @State private var newBlockMinutes: Int
    @State private var newBlockFocus: String
    @State private var newBlockPitchArea: String
    @State private var newBlockDetails: String
    @State private var newBlockIntensity: Int
    @State private var selectedPositions: Set<PlayerPosition>

    init(session: TrainingSession? = nil) {
        self.session = session
        _title = State(initialValue: session?.title ?? "")
        _date = State(initialValue: session?.date ?? Date())
        _objective = State(initialValue: session?.objective ?? "")
        _weather = State(initialValue: session?.weather ?? "Clear")
        _blocks = State(initialValue: session?.blocks ?? [])
        _selectedDrillID = State(initialValue: session?.blocks.first?.drillID)
        _selectedDiagramID = State(initialValue: session?.blocks.first?.diagramID)
        _newBlockTopic = State(initialValue: "")
        _newBlockMinutes = State(initialValue: 15)
        _newBlockFocus = State(initialValue: "")
        _newBlockPitchArea = State(initialValue: "")
        _newBlockDetails = State(initialValue: "")
        _newBlockIntensity = State(initialValue: 3)
        _selectedPositions = State(initialValue: Set<PlayerPosition>())
    }

    var body: some View {
        Form {
            Section("Session") {
                TextField("Title", text: $title)
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Weather", text: $weather)
                LabeledContent("Team", value: store.selectedTeam.name)
                LabeledContent("Time of Day", value: date.formatted(date: .omitted, time: .shortened))
            }

            Section("Session Description") {
                TextEditor(text: $objective)
                    .frame(minHeight: 120)
            }

            Section {
                if store.teamDrills.isEmpty {
                    Text("Add team or shared drills before building this session plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Drill", selection: selectedDrillBinding) {
                        ForEach(store.teamDrills) { drill in
                            Text(drill.title).tag(Optional(drill.id))
                        }
                    }
                    .onChange(of: selectedDrillID) { drillID in
                        if let drillID, let drill = store.drill(for: drillID) {
                            clearSectionDraft()
                            applyDrillDefaults(drill)
                        }
                    }

                    if !selectedDrillDiagrams.isEmpty {
                        Picker("Field Diagram", selection: selectedDiagramBinding) {
                            Text("None").tag(UUID?.none)
                            ForEach(selectedDrillDiagrams) { diagram in
                                Text(diagram.title).tag(Optional(diagram.id))
                            }
                        }
                    } else if selectedDrillID != nil {
                        Text("No field diagrams attached to this drill yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Section topic", text: $newBlockTopic, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Part of pitch", text: $newBlockPitchArea)
                    Stepper("\(newBlockMinutes) minutes", value: $newBlockMinutes, in: 1...90)
                    Stepper("Intensity \(newBlockIntensity) / 5", value: $newBlockIntensity, in: 1...5)
                    TextField("Coaching focus", text: $newBlockFocus, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Section description", text: $newBlockDetails, axis: .vertical)
                        .lineLimit(2...5)

                    DisclosureGroup("Positions") {
                        ForEach(PlayerPosition.allCases) { position in
                            Toggle(position.rawValue, isOn: selectedPositionBinding(for: position))
                        }
                    }

                    Button {
                        addSelectedDrillBlock()
                    } label: {
                        Label(blocks.count >= 6 ? "Maximum 6 Sections" : "Add Section to Plan", systemImage: "plus.circle")
                    }
                    .disabled(selectedDrillID == nil || blocks.count >= 6)
                }
            } header: {
                Text("Build Sections From Drills")
            } footer: {
                Text("\(blocks.count) / 6 sections, \(planMinutes) total minutes")
            }

            if !blocks.isEmpty {
                Section {
                    ForEach($blocks) { $block in
                        SessionBlockEditorRow(
                            block: $block,
                            drill: store.drill(for: block.drillID),
                            diagrams: diagrams(for: block)
                        )
                    }
                    .onDelete { offsets in
                        blocks.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        blocks.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Session Plan")
                } footer: {
                    Text("Total practice time: \(planMinutes) minutes")
                }
            }
        }
        .onAppear(perform: prepareDefaultDrillSelection)
        .navigationTitle(session == nil ? "New Session" : "Edit Session")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !blocks.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    EditButton()
                }
            }
        }
    }

    private func save() {
        if let session {
            var updated = session
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.date = date
            updated.objective = objective
            updated.weather = cleanWeather
            updated.blocks = blocks
            store.updateSession(updated)
        } else {
            store.addSession(title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date, objective: objective, weather: cleanWeather, blocks: blocks)
        }
    }

    private var selectedDrillBinding: Binding<UUID?> {
        Binding {
            selectedDrillID
        } set: { newValue in
            selectedDrillID = newValue
        }
    }

    private var selectedDiagramBinding: Binding<UUID?> {
        Binding {
            selectedDiagramID
        } set: { newValue in
            selectedDiagramID = newValue
        }
    }

    private var cleanWeather: String {
        let trimmed = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private var planMinutes: Int {
        blocks.reduce(0) { $0 + $1.minutes }
    }

    private var selectedDrillDiagrams: [TacticsDiagram] {
        guard let selectedDrillID, let drill = store.drill(for: selectedDrillID) else { return [] }
        return store.diagrams(for: drill)
    }

    private func prepareDefaultDrillSelection() {
        guard selectedDrillID == nil, let drill = store.teamDrills.first else { return }
        selectedDrillID = drill.id
        applyDrillDefaults(drill)
    }

    private func addSelectedDrillBlock() {
        guard let drillID = selectedDrillID else { return }
        guard blocks.count < 6 else { return }
        let cleanFocus = newBlockFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTopic = newBlockTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPitchArea = newBlockPitchArea.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = newBlockDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFocus = store.drill(for: drillID)?.coachingPoints.first ?? "Run the drill with game speed."
        let fallbackTopic = store.drill(for: drillID)?.title ?? "Training Section"
        let positions = PlayerPosition.allCases.filter { selectedPositions.contains($0) }

        blocks.append(
            TrainingBlock(
                id: UUID(),
                drillID: drillID,
                minutes: newBlockMinutes,
                focus: cleanFocus.isEmpty ? fallbackFocus : cleanFocus,
                diagramID: selectedDiagramID,
                topic: cleanTopic.isEmpty ? fallbackTopic : cleanTopic,
                positions: positions,
                pitchArea: cleanPitchArea,
                details: cleanDetails,
                intensity: newBlockIntensity
            )
        )

        if let drill = store.drill(for: drillID) {
            clearSectionDraft()
            applyDrillDefaults(drill)
        }
    }

    private func clearSectionDraft() {
        newBlockTopic = ""
        newBlockFocus = ""
        newBlockPitchArea = ""
        newBlockDetails = ""
        newBlockIntensity = 3
        selectedPositions.removeAll()
    }

    private func applyDrillDefaults(_ drill: Drill) {
        newBlockMinutes = drill.durationMinutes
        if newBlockTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockTopic = drill.title
        }
        if newBlockFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockFocus = drill.coachingPoints.first ?? ""
        }
        if newBlockPitchArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockPitchArea = drill.fieldSize
        }
        if newBlockDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newBlockDetails = drill.fieldSetup
        }
        selectedDiagramID = store.diagrams(for: drill).first?.id
    }

    private func diagrams(for block: TrainingBlock) -> [TacticsDiagram] {
        guard let drill = store.drill(for: block.drillID) else { return [] }
        return store.diagrams(for: drill)
    }

    private func selectedPositionBinding(for position: PlayerPosition) -> Binding<Bool> {
        Binding {
            selectedPositions.contains(position)
        } set: { isSelected in
            if isSelected {
                selectedPositions.insert(position)
            } else {
                selectedPositions.remove(position)
            }
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

struct SessionBlockEditorRow: View {
    @Binding var block: TrainingBlock
    let drill: Drill?
    let diagrams: [TacticsDiagram]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.topic.isEmpty ? drill?.title ?? "Deleted Drill" : block.topic)
                        .font(.headline)
                    Text(drill?.category.rawValue ?? "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(block.minutes) min", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Section topic", text: $block.topic, axis: .vertical)
                .lineLimit(1...3)
            Stepper("Duration \(block.minutes) min", value: $block.minutes, in: 1...90)
            Stepper("Intensity \(block.intensity) / 5", value: $block.intensity, in: 1...5)

            TextField("Part of pitch", text: $block.pitchArea)

            TextField("Block focus", text: $block.focus, axis: .vertical)
                .lineLimit(2...4)

            TextField("Description", text: $block.details, axis: .vertical)
                .lineLimit(2...5)

            if !diagrams.isEmpty {
                Picker("Field Diagram", selection: diagramBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(diagrams) { diagram in
                        Text(diagram.title).tag(Optional(diagram.id))
                    }
                }
            }

            DisclosureGroup("Positions") {
                ForEach(PlayerPosition.allCases) { position in
                    Toggle(position.rawValue, isOn: positionBinding(for: position))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var diagramBinding: Binding<UUID?> {
        Binding {
            block.diagramID
        } set: { newValue in
            block.diagramID = newValue
        }
    }

    private func positionBinding(for position: PlayerPosition) -> Binding<Bool> {
        Binding {
            block.positions.contains(position)
        } set: { isSelected in
            if isSelected {
                if !block.positions.contains(position) {
                    block.positions.append(position)
                }
            } else {
                block.positions.removeAll { $0 == position }
            }
        }
    }
}
