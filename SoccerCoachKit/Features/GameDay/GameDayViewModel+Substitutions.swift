import Foundation

extension GameDayViewModel {
    // MARK: - Substitutions

    func addReminder() {
        guard let outID = selectedOutPlayerID, let inID = selectedInPlayerID else { return }
        reminders.append(SubReminder(id: UUID(), minute: newReminderMinute, outPlayerID: outID, inPlayerID: inID, triggered: false))
        rescheduleNotifications()
    }

    func applySubstitution(_ reminder: SubReminder) {
        // Only clear the reminder if the swap actually happened (it no-ops when
        // the incoming/outgoing player is no longer available).
        if substitute(outID: reminder.outPlayerID, inID: reminder.inPlayerID, note: "Reminder") {
            reminders.removeAll { $0.id == reminder.id }
            rescheduleNotifications()
        }
    }

    func recordSelectedSub() {
        guard let outID = selectedOutPlayerID, let inID = selectedInPlayerID else { return }
        substitute(outID: outID, inID: inID, note: "Manual sub")
    }

    func undoLastSub() {
        guard canUndoLastSub, let last = subLog.first else { return }
        settle()
        starterIDs.remove(last.inPlayerID)
        starterIDs.insert(last.outPlayerID)
        subLog.removeFirst()
        normalizeSelections()
    }

    func deleteReminder(_ reminder: SubReminder) {
        reminders.removeAll { $0.id == reminder.id }
        rescheduleNotifications()
    }

    @discardableResult
    private func substitute(outID: UUID, inID: UUID, note: String) -> Bool {
        guard starterIDs.contains(outID), !starterIDs.contains(inID) else { return false }
        guard playerStatuses[outID, default: .available] == .available, playerStatuses[inID, default: .available] == .available else { return false }
        settle()
        starterIDs.remove(outID)
        starterIDs.insert(inID)
        subLog.insert(
            SubLogEntry(id: UUID(), time: elapsedSeconds, outPlayerID: outID, inPlayerID: inID, outName: playerName(outID), inName: playerName(inID), note: note),
            at: 0
        )
        normalizeSelections()
        return true
    }

    // MARK: - Drag and drop

    func handlePlayerDrop(_ providers: [NSItemProvider], target: LineupDropTarget) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }

        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let value = object as? NSString, let playerID = UUID(uuidString: value as String) else { return }

            DispatchQueue.main.async {
                self?.moveDroppedPlayer(playerID, target: target)
            }
        }

        return true
    }

    private func moveDroppedPlayer(_ playerID: UUID, target: LineupDropTarget) {
        guard let player = roster.first(where: { $0.id == playerID }) else { return }

        switch target {
        case .bench:
            moveToBench(player)
        case .starters:
            guard status(for: player) == .available else { return }

            if starterIDs.contains(player.id) {
                return
            }

            if starterIDs.count < playersOnField {
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
            } else if starterIDs.count < playersOnField {
                moveToStarter(player)
            }
        }
    }
}
