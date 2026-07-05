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

            Button {
                viewModel.clearLines()
            } label: {
                Label("Clear Lines", systemImage: "scribble.variable")
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
                Button("Game Plan") {
                    viewModel.attachCurrentDiagram(sessionID: nil, drillID: nil, in: store)
                }

                if !store.teamSessions.isEmpty {
                    Menu("Training Session") {
                        ForEach(store.teamSessions) { session in
                            Button(session.title) {
                                viewModel.attachCurrentDiagram(sessionID: session.id, drillID: nil, in: store)
                            }
                        }
                    }
                }

                if !store.teamDrills.isEmpty {
                    Menu("Drill") {
                        ForEach(store.teamDrills) { drill in
                            Button(drill.title) {
                                viewModel.attachCurrentDiagram(sessionID: nil, drillID: drill.id, in: store)
                            }
                        }
                    }
                }
            } label: {
                Label(viewModel.attachmentTitle(in: store), systemImage: "paperclip")
                    .font(.caption)
            }

            Picker("Board Tool", selection: $viewModel.tool) {
                ForEach(BoardTool.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.helpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding()
        .background(Color.cardBackground)
    }
}
