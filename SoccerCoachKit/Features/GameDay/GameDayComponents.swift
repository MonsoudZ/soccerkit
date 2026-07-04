import SwiftUI
import UniformTypeIdentifiers

struct GameClockPanel: View {
    let elapsedSeconds: Int
    let periodSeconds: Int
    let periodLabel: String
    let periodCount: Int
    let advanceLabel: String
    let canAdvancePeriod: Bool
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
                    Text("\(periodLabel) of \(periodCount) · \(formatClock(periodSeconds)) this period")
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
                    Label(advanceLabel, systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canAdvancePeriod)

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status == .available && isStarter ? "On the field" : status.rawValue)
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
