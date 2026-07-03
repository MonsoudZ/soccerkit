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
        let pageBottom = pageSize.height - margin
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        var lines = headerLines(team: team, playerCount: players.count)
        for player in players.sorted(by: { $0.number < $1.number }) {
            lines.append(contentsOf: playerLines(for: player))
        }

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin

            for line in lines {
                if line.startsBlock {
                    // Gap before each player, and don't orphan the header line
                    // at the very bottom of a page.
                    if y > margin { y += 12 }
                    if pageBottom - y < 64 {
                        ctx.beginPage()
                        y = margin
                    }
                }

                let height = drawText(line.text, font: line.font, color: line.color, x: margin, y: y, width: contentWidth, draw: false)
                if y + height > pageBottom {
                    ctx.beginPage()
                    y = margin
                }
                _ = drawText(line.text, font: line.font, color: line.color, x: margin, y: y, width: contentWidth, draw: true)
                y += height + line.spacingAfter
            }
        }
    }

    private struct PDFLine {
        let text: String
        let font: UIFont
        let color: UIColor
        let spacingAfter: CGFloat
        let startsBlock: Bool
    }

    private static func headerLines(team: Team, playerCount: Int) -> [PDFLine] {
        let subtitle = "\(team.ageGroup.rawValue) · \(team.season) · \(playerCount) player\(playerCount == 1 ? "" : "s")"
        return [
            PDFLine(text: team.name, font: .boldSystemFont(ofSize: 22), color: .label, spacingAfter: 2, startsBlock: false),
            PDFLine(text: subtitle, font: .systemFont(ofSize: 12), color: .secondaryLabel, spacingAfter: 18, startsBlock: false)
        ]
    }

    /// One `PDFLine` per field, so a long roster (or a player with lengthy
    /// notes) paginates line-by-line instead of clipping an oversized block.
    private static func playerLines(for player: Player) -> [PDFLine] {
        var lines = [
            PDFLine(text: "#\(player.number)  \(player.name)", font: .boldSystemFont(ofSize: 14), color: .label, spacingAfter: 1, startsBlock: true),
            PDFLine(text: positionName(player.position), font: .systemFont(ofSize: 11), color: .secondaryLabel, spacingAfter: 4, startsBlock: false)
        ]

        let details: [(String, String)] = [
            ("Guardian", join(player.guardian, player.guardianPhone, player.guardianEmail)),
            ("Secondary", join(player.secondaryContactName, player.secondaryContactPhone)),
            ("Emergency", emergencyLine(player)),
            ("Allergies", player.allergies),
            ("Medical", player.medicalNotes),
            ("Notes", player.notes)
        ]
        for (label, value) in details where !value.isEmpty {
            lines.append(PDFLine(text: "\(label): \(value)", font: .systemFont(ofSize: 11), color: .label, spacingAfter: 2, startsBlock: false))
        }
        return lines
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
