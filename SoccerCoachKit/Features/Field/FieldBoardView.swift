import SwiftUI

struct FieldBoardView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = FieldBoardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            boardToolbar

            FieldCanvas(
                tool: viewModel.tool,
                roster: store.roster,
                players: $viewModel.players,
                zones: $viewModel.zones,
                lines: $viewModel.lines,
                equipment: $viewModel.equipment,
                draftLine: $viewModel.draftLine,
                opponentCount: $viewModel.opponentCount,
                coneCount: $viewModel.coneCount,
                zoneCount: $viewModel.zoneCount
            )
            .padding()
        }
        .screenBackground()
        .onAppear { viewModel.ensureDiagramLoaded(in: store) }
        .onChange(of: store.selectedTeamID) { _ in
            viewModel.selectedDiagramID = nil
            viewModel.ensureDiagramLoaded(in: store)
        }
        .onChange(of: viewModel.selectedDiagramID) { _ in
            viewModel.loadSelectedDiagram(in: store)
        }
        .toolbar {
            Button {
                viewModel.saveCurrentDiagram(in: store)
            } label: {
                Label("Save Diagram", systemImage: "square.and.arrow.down")
            }

            Button {
                viewModel.duplicateCurrentDiagram(in: store)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.currentDiagram(in: store) == nil)

            Menu {
                Button("Prepare Image") {
                    viewModel.prepareImageExport(in: store)
                }

                Button("Prepare PDF") {
                    viewModel.preparePDFExport(in: store)
                }

                if let exportURL = viewModel.exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                viewModel.resetCurrentBoard(in: store)
            } label: {
                Label("Reset to Team Defaults", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                viewModel.deleteCurrentDiagram(in: store)
            } label: {
                Label("Delete Diagram", systemImage: "trash")
            }
            .disabled(viewModel.currentDiagram(in: store) == nil)
        }
        // Context row: pick what to place on the board, add a diagram, or clear
        // drawn lines — the field's quick actions, above the tab bar.
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                ForEach(BoardTool.allCases) { boardTool in
                    Button {
                        viewModel.tool = boardTool
                    } label: {
                        Label(boardTool.rawValue, systemImage: boardTool.symbol)
                    }
                    .tint(viewModel.tool == boardTool ? Color.brand : Color.secondary)
                    .accessibilityAddTraits(viewModel.tool == boardTool ? [.isButton, .isSelected] : .isButton)
                }
                Spacer()
                Button {
                    viewModel.clearLines()
                } label: {
                    Label("Clear Lines", systemImage: "scribble.variable")
                }
            }
        }
    }

    /// True when the current diagram isn't attached to a game, session, or drill.
    private var isDetached: Bool {
        guard let diagram = viewModel.currentDiagram(in: store) else { return true }
        return diagram.sessionID == nil && diagram.drillID == nil && diagram.gameID == nil
    }

    private var boardToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Diagram", selection: $viewModel.selectedDiagramID) {
                    ForEach(store.teamDiagrams) { diagram in
                        Text(diagram.title).tag(Optional(diagram.id))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    viewModel.createNewDiagram(in: store)
                } label: {
                    Label("New Diagram", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            TextField("Diagram title", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)

            TextField("Diagram notes", text: $viewModel.notes)
                .textFieldStyle(.roundedBorder)

            Menu {
                Button {
                    viewModel.attachCurrentDiagram(in: store)
                } label: {
                    Label("Game Plan (unattached)", systemImage: isDetached ? "checkmark" : "square.dashed")
                }

                if !store.teamGames.isEmpty {
                    Menu("Game / Fixture") {
                        ForEach(store.teamGames) { game in
                            Button {
                                viewModel.attachCurrentDiagram(gameID: game.id, in: store)
                            } label: {
                                Label(
                                    "vs \(game.opponent) · \(game.date.formatted(date: .abbreviated, time: .omitted))",
                                    systemImage: viewModel.currentDiagram(in: store)?.gameID == game.id ? "checkmark" : "soccerball"
                                )
                            }
                        }
                    }
                }

                if !store.teamSessions.isEmpty {
                    Menu("Training Session") {
                        ForEach(store.teamSessions) { session in
                            Button {
                                viewModel.attachCurrentDiagram(sessionID: session.id, in: store)
                            } label: {
                                Label(session.title, systemImage: viewModel.currentDiagram(in: store)?.sessionID == session.id ? "checkmark" : "figure.run")
                            }
                        }
                    }
                }

                if !store.teamDrills.isEmpty {
                    Menu("Drill") {
                        ForEach(store.teamDrills) { drill in
                            Button {
                                viewModel.attachCurrentDiagram(drillID: drill.id, in: store)
                            } label: {
                                Label(drill.title, systemImage: viewModel.currentDiagram(in: store)?.drillID == drill.id ? "checkmark" : "sportscourt")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "paperclip")
                    Text("Attached to:")
                        .foregroundStyle(.secondary)
                    Text(viewModel.attachmentTitle(in: store))
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.screenBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
            }

            Text(viewModel.helpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding()
        .background(Color.cardBackground)
    }
}
