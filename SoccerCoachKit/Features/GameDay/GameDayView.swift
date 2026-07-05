import SwiftUI

struct GameDayView: View {
    @EnvironmentObject private var store: AppStore
    // Owned by ContentView so the live match survives leaving and returning to
    // this screen; only reset on first setup or a team change.
    @ObservedObject var viewModel: GameDayViewModel

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GameClockPanel(
                    elapsedSeconds: viewModel.elapsedSeconds,
                    periodSeconds: viewModel.periodSeconds,
                    periodLabel: viewModel.currentPeriodLabel,
                    periodCount: viewModel.periodCount,
                    advanceLabel: viewModel.advancePeriodLabel,
                    canAdvancePeriod: !viewModel.isLastPeriod,
                    targetMinutes: viewModel.defaultGameMinutes,
                    isRunning: viewModel.isRunning,
                    starters: viewModel.availableStarterPlayers.count,
                    playersOnField: viewModel.playersOnField,
                    startAction: { viewModel.start() },
                    pauseAction: { viewModel.pause() },
                    resetAction: { viewModel.resetGameClock() },
                    nextPeriodAction: { viewModel.advancePeriod() },
                    resetPeriodAction: { viewModel.resetPeriodClock() }
                )

                quickSubSection
                lineupSection
                reminderSection
                playingTimeSection

                if !viewModel.subLog.isEmpty {
                    subLogSection
                }
            }
            .padding()
        }
        .screenBackground()
        .onAppear {
            viewModel.prepareIfNeeded(with: store)
            viewModel.requestNotificationAuthorization()
        }
        .onChange(of: store.selectedTeamID) { _ in
            viewModel.reset(with: store)
        }
        .onChange(of: store.roster) { _ in
            viewModel.syncRoster(with: store)
        }
        .onReceive(ticker) { _ in
            viewModel.tick()
        }
        .alert("Substitution Reminder", isPresented: $viewModel.showReminder) {
            Button("Record Sub") {
                viewModel.acknowledgeReminder(record: true)
            }
            Button("Keep Lineup", role: .cancel) {
                viewModel.acknowledgeReminder(record: false)
            }
        } message: {
            Text(viewModel.activeReminderText)
        }
        .alert("Sub Coming Up", isPresented: $viewModel.showPreAlert) {
            Button("Got It", role: .cancel) {
                viewModel.dismissPreAlert()
            }
        } message: {
            Text(viewModel.activePreAlertText)
        }
    }

    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lineup")

            HStack {
                Label("\(store.selectedTeam.ageGroup.rawValue): \(viewModel.playersOnField)v\(viewModel.playersOnField)", systemImage: "shield")
                Spacer()
                Text("\(viewModel.availableStarterPlayers.count) / \(viewModel.playersOnField) available starters")
                    .foregroundStyle(viewModel.availableStarterPlayers.count == viewModel.playersOnField ? Color.secondary : Color.orange)
            }
            .font(.subheadline)

            Picker("Formation", selection: $viewModel.formation) {
                ForEach(LineupFormation.allCases) { formation in
                    Text(formation.rawValue).tag(formation)
                }
            }
            .pickerStyle(.segmented)

            LineupPitchView(
                players: viewModel.starterPlayers,
                formation: viewModel.formation,
                playersOnField: viewModel.playersOnField,
                playingSeconds: viewModel.playingSeconds,
                statuses: viewModel.playerStatuses,
                dropAction: { providers in
                    viewModel.handlePlayerDrop(providers, target: .starters)
                },
                slotDropAction: { playerID, providers in
                    viewModel.handlePlayerDrop(providers, target: .starterSlot(playerID))
                }
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                LineupColumn(
                    title: "Starting Team",
                    symbol: "figure.soccer",
                    players: viewModel.starterPlayers,
                    playingSeconds: viewModel.playingSeconds,
                    statuses: viewModel.playerStatuses,
                    actionTitle: "Bench",
                    actionSymbol: "arrow.down.circle",
                    action: viewModel.moveToBench,
                    statusAction: viewModel.setPlayerStatus,
                    dropAction: { providers in
                        viewModel.handlePlayerDrop(providers, target: .starters)
                    },
                    playerDropAction: { player, providers in
                        viewModel.handlePlayerDrop(providers, target: .starterSlot(player.id))
                    }
                )

                LineupColumn(
                    title: "Bench",
                    symbol: "person.2",
                    players: viewModel.benchPlayers,
                    playingSeconds: viewModel.playingSeconds,
                    statuses: viewModel.playerStatuses,
                    actionTitle: "Start",
                    actionSymbol: "arrow.up.circle",
                    action: viewModel.moveToStarter,
                    statusAction: viewModel.setPlayerStatus,
                    dropAction: { providers in
                        viewModel.handlePlayerDrop(providers, target: .bench)
                    },
                    playerDropAction: { _, providers in
                        viewModel.handlePlayerDrop(providers, target: .bench)
                    }
                )
            }
        }
    }

    private var quickSubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Quick Sub")

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    viewModel.selectSuggestedSub()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Suggest balanced sub")
                                .font(.subheadline.weight(.semibold))
                            Text(viewModel.suggestedSubText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.suggestedSub == nil)

                Picker("Sub Out", selection: $viewModel.selectedOutPlayerID) {
                    Text("Choose starter").tag(UUID?.none)
                    ForEach(viewModel.availableStarterPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Picker("Sub In", selection: $viewModel.selectedInPlayerID) {
                    Text("Choose bench").tag(UUID?.none)
                    ForEach(viewModel.availableBenchPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                HStack {
                    Button {
                        viewModel.recordSelectedSub()
                    } label: {
                        Label("Record Sub", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedOutPlayerID == nil || viewModel.selectedInPlayerID == nil)

                    Button {
                        viewModel.undoLastSub()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUndoLastSub)
                }
            }
            .padding()
            .surfaceStyle()
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Sub Reminders")

            VStack(alignment: .leading, spacing: 12) {
                Stepper("Minute \(viewModel.newReminderMinute)", value: $viewModel.newReminderMinute, in: 1...max(viewModel.defaultGameMinutes, 1))

                Stepper("Alert \(viewModel.subAlertLeadMinutes) min early", value: $viewModel.subAlertLeadMinutes, in: 0...10)

                Picker("Sub Out", selection: $viewModel.selectedOutPlayerID) {
                    Text("Choose player").tag(UUID?.none)
                    ForEach(viewModel.availableStarterPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Picker("Sub In", selection: $viewModel.selectedInPlayerID) {
                    Text("Choose player").tag(UUID?.none)
                    ForEach(viewModel.availableBenchPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }

                Button {
                    viewModel.addReminder()
                } label: {
                    Label("Add Reminder", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedOutPlayerID == nil || viewModel.selectedInPlayerID == nil)
            }
            .padding()
            .surfaceStyle()

            if viewModel.reminders.isEmpty {
                Text("No reminders set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.reminders.sorted { $0.minute < $1.minute }) { reminder in
                        ReminderRow(reminder: reminder, outName: viewModel.playerName(reminder.outPlayerID), inName: viewModel.playerName(reminder.inPlayerID)) {
                            viewModel.applySubstitution(reminder)
                        } deleteAction: {
                            viewModel.deleteReminder(reminder)
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
                ForEach(viewModel.roster) { player in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("#\(player.number)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(status: viewModel.status(for: player), isStarter: viewModel.starterIDs.contains(player.id))
                        }
                        Text(player.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(formatClock(viewModel.playingSeconds[player.id, default: 0]))
                            .font(.title3.monospacedDigit().weight(.bold))

                        if viewModel.minimumSeconds(for: player) > 0 {
                            ProgressView(value: viewModel.goalProgress(for: player))
                                .tint(viewModel.isAtRiskOfMissingGoal(player) ? .orange : (viewModel.hasReachedGoal(player) ? .green : .accentColor))
                            if viewModel.isAtRiskOfMissingGoal(player) {
                                Label("Behind minutes goal", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            } else {
                                Text("Goal \(viewModel.minimumSeconds(for: player) / 60)m")
                                    .font(.caption2)
                                    .foregroundStyle(viewModel.hasReachedGoal(player) ? .green : .secondary)
                            }
                        }

                        Menu {
                            ForEach(GamePlayerStatus.allCases) { status in
                                Button(status.rawValue) {
                                    viewModel.setPlayerStatus(player, status)
                                }
                            }
                        } label: {
                            Label(viewModel.status(for: player).rawValue, systemImage: "person.crop.circle.badge.questionmark")
                                .font(.caption)
                                .foregroundStyle(viewModel.status(for: player).color)
                        }
                    }
                    .padding()
                    .surfaceStyle()
                }
            }
        }
    }

    private var subLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Sub Log")

            ForEach(viewModel.subLog) { entry in
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
                .surfaceStyle()
            }
        }
    }
}
