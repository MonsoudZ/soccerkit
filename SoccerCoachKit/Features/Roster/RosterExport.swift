import SwiftUI
import UIKit

/// Generates shareable CSV and PDF exports of a team's roster. Mirrors the
/// temp-file + system-share pattern used by the field-diagram export.
enum RosterExporter {

    // MARK: - CSV

    static func csvData(for players: [Player], team: Team) -> Data {
        let headers = [
            "Number", "Name", "Position", "Guardian", "Guardian Phone", "Guardian Email",
            "Secondary Contact", "Secondary Phone",
            "Emergency Contact", "Emergency Phone", "Emergency Relation",
            "Allergies", "Medical Notes", "Notes"
        ]

        var rows = [headers.map(escapeCSV).joined(separator: ",")]
        for player in players.sorted(by: { $0.number < $1.number }) {
            let fields = [
                String(player.number),
                player.name,
                player.position.rawValue,
                player.guardian,
                player.guardianPhone,
                player.guardianEmail,
                player.secondaryContactName,
                player.secondaryContactPhone,
                player.emergencyContactName,
                player.emergencyContactPhone,
                player.emergencyContactRelation,
                player.allergies,
                player.medicalNotes,
                player.notes
            ]
            rows.append(fields.map(escapeCSV).joined(separator: ","))
        }

        let csv = rows.joined(separator: "\r\n") + "\r\n"
        // Prepend a UTF-8 BOM so spreadsheet apps open accented names correctly.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        return data
    }

    /// RFC-4180 escaping: wrap a field in quotes and double any embedded quotes
    /// only when it contains a comma, quote, or newline.
    private static func escapeCSV(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - PDF

    static func pdfData(for players: [Player], team: Team) -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter, 72 dpi
        let margin: CGFloat = 44
        let contentWidth = pageSize.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = drawHeader(team: team, playerCount: players.count, x: margin, y: margin, width: contentWidth)

            for player in players.sorted(by: { $0.number < $1.number }) {
                let height = renderPlayer(player, x: margin, y: 0, width: contentWidth, draw: false)
                if y + height > pageSize.height - margin {
                    ctx.beginPage()
                    y = margin
                }
                y += renderPlayer(player, x: margin, y: y, width: contentWidth, draw: true)
                y += 14
            }
        }
    }

    private static func drawHeader(team: Team, playerCount: Int, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var cursor = y
        cursor += drawText(team.name, font: .boldSystemFont(ofSize: 22), color: .label, x: x, y: cursor, width: width, draw: true)
        cursor += 2
        let subtitle = "\(team.ageGroup.rawValue) · \(team.season) · \(playerCount) player\(playerCount == 1 ? "" : "s")"
        cursor += drawText(subtitle, font: .systemFont(ofSize: 12), color: .secondaryLabel, x: x, y: cursor, width: width, draw: true)
        return cursor + 18
    }

    /// Lays out a single player block. When `draw` is false it only measures,
    /// so pagination and drawing use the exact same layout.
    @discardableResult
    private static func renderPlayer(_ player: Player, x: CGFloat, y: CGFloat, width: CGFloat, draw: Bool) -> CGFloat {
        var cursor = y
        cursor += drawText("#\(player.number)  \(player.name)", font: .boldSystemFont(ofSize: 14), color: .label, x: x, y: cursor, width: width, draw: draw)
        cursor += 1
        cursor += drawText(positionName(player.position), font: .systemFont(ofSize: 11), color: .secondaryLabel, x: x, y: cursor, width: width, draw: draw)
        cursor += 4

        let details: [(String, String)] = [
            ("Guardian", join(player.guardian, player.guardianPhone, player.guardianEmail)),
            ("Secondary", join(player.secondaryContactName, player.secondaryContactPhone)),
            ("Emergency", emergencyLine(player)),
            ("Allergies", player.allergies),
            ("Medical", player.medicalNotes),
            ("Notes", player.notes)
        ]
        for (label, value) in details where !value.isEmpty {
            cursor += drawText("\(label): \(value)", font: .systemFont(ofSize: 11), color: .label, x: x, y: cursor, width: width, draw: draw)
            cursor += 2
        }
        return cursor - y
    }

    @discardableResult
    private static func drawText(_ text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat, draw: Bool) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        if draw {
            attributed.draw(
                with: CGRect(x: x, y: y, width: width, height: ceil(bounds.height)),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        return ceil(bounds.height)
    }

    private static func join(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func emergencyLine(_ player: Player) -> String {
        let base = join(player.emergencyContactName, player.emergencyContactPhone)
        guard !player.emergencyContactRelation.isEmpty else { return base }
        return base.isEmpty ? player.emergencyContactRelation : "\(base) (\(player.emergencyContactRelation))"
    }

    private static func positionName(_ position: PlayerPosition) -> String {
        switch position {
        case .goalkeeper: return "Goalkeeper"
        case .defender: return "Defender"
        case .midfielder: return "Midfielder"
        case .forward: return "Forward"
        }
    }

    // MARK: - File

    static func write(_ data: Data, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func fileName(for team: Team, extension fileExtension: String) -> String {
        let base = team.name
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return "\(base.isEmpty ? "roster" : base)-roster.\(fileExtension)"
    }
}

/// Identifiable wrapper so a prepared export URL can drive a `.sheet(item:)`.
struct RosterExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents the system share sheet for an exported roster file.
struct RosterShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
