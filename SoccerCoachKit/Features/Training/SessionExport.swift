import SwiftUI
import UIKit

/// Renders a full training-session plan as a shareable PDF for assistant
/// coaches: the objective plus every timed block with its drill, setup,
/// coaching focus, and points.
enum SessionExporter {
    // Explicit colors — a PDF is always on white paper, so dynamic colors like
    // `.label` (which resolve to white in dark mode) must not be used.
    private static let primaryColor = UIColor.black
    private static let secondaryColor = UIColor(white: 0.35, alpha: 1)

    @MainActor
    static func pdfData(for session: TrainingSession, in store: AppStore) -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter, 72 dpi
        let margin: CGFloat = 44
        let contentWidth = pageSize.width - margin * 2
        let pageBottom = pageSize.height - margin
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let lines = planLines(for: session, in: store)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin

            for line in lines {
                if line.startsBlock {
                    if y > margin { y += 12 }
                    if pageBottom - y < 72 {
                        ctx.beginPage()
                        y = margin
                    }
                }

                let height = drawText(line.text, font: line.font, color: line.color, x: margin + line.indent, y: y, width: contentWidth - line.indent, draw: false)
                if y + height > pageBottom {
                    ctx.beginPage()
                    y = margin
                }
                _ = drawText(line.text, font: line.font, color: line.color, x: margin + line.indent, y: y, width: contentWidth - line.indent, draw: true)
                y += height + line.spacingAfter
            }
        }
    }

    private struct PDFLine {
        let text: String
        let font: UIFont
        let color: UIColor
        var spacingAfter: CGFloat = 2
        var indent: CGFloat = 0
        var startsBlock: Bool = false
    }

    @MainActor
    private static func planLines(for session: TrainingSession, in store: AppStore) -> [PDFLine] {
        var lines: [PDFLine] = []

        // Header.
        lines.append(PDFLine(text: session.title, font: .boldSystemFont(ofSize: 22), color: primaryColor, spacingAfter: 2))
        let totalMinutes = session.blocks.reduce(0) { $0 + $1.minutes }
        let subtitle = "\(store.teamName(for: session.teamID)) · \(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.weather) · \(totalMinutes) min"
        lines.append(PDFLine(text: subtitle, font: .systemFont(ofSize: 12), color: secondaryColor, spacingAfter: 12))

        if !session.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(PDFLine(text: "Objective", font: .boldSystemFont(ofSize: 13), color: primaryColor, spacingAfter: 2))
            lines.append(PDFLine(text: session.objective, font: .systemFont(ofSize: 12), color: primaryColor, spacingAfter: 12))
        }

        if session.blocks.isEmpty {
            lines.append(PDFLine(text: "No sections planned.", font: .systemFont(ofSize: 12), color: secondaryColor))
            return lines
        }

        // One block per section.
        for (index, block) in session.blocks.enumerated() {
            let drill = store.drill(for: block.drillID)
            let title = block.topic.isEmpty ? (drill?.title ?? "Section") : block.topic

            lines.append(PDFLine(
                text: "\(index + 1). \(title)",
                font: .boldSystemFont(ofSize: 14), color: primaryColor, spacingAfter: 1, startsBlock: true
            ))
            lines.append(PDFLine(
                text: "\(block.minutes) min · Intensity \(block.intensity)/5",
                font: .systemFont(ofSize: 11), color: secondaryColor, spacingAfter: 3
            ))

            if let drill {
                lines.append(detail("Drill", "\(drill.title) (\(drill.category.rawValue))"))
            }
            if !block.pitchArea.isEmpty { lines.append(detail("Area", block.pitchArea)) }
            if !block.positions.isEmpty {
                lines.append(detail("Positions", block.positions.map(\.rawValue).joined(separator: ", ")))
            }
            if !block.focus.isEmpty { lines.append(detail("Focus", block.focus)) }
            if !block.details.isEmpty { lines.append(detail("Notes", block.details)) }

            if let points = drill?.coachingPoints, !points.isEmpty {
                lines.append(PDFLine(text: "Coaching points:", font: .systemFont(ofSize: 11).withBold(), color: primaryColor, spacingAfter: 1, indent: 4))
                for point in points {
                    lines.append(PDFLine(text: "• \(point)", font: .systemFont(ofSize: 11), color: primaryColor, spacingAfter: 1, indent: 10))
                }
            }
            if let diagram = store.diagram(for: block.diagramID) {
                lines.append(detail("Diagram", diagram.title))
            }
        }

        return lines
    }

    private static func detail(_ label: String, _ value: String) -> PDFLine {
        PDFLine(text: "\(label): \(value)", font: .systemFont(ofSize: 11), color: primaryColor, spacingAfter: 2, indent: 4)
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

    static func fileName(for session: TrainingSession) -> String {
        let base = session.title
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return "\(base.isEmpty ? "session" : base)-plan.pdf"
    }
}

private extension UIFont {
    func withBold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Identifiable wrapper so a prepared export URL can drive a `.sheet(item:)`.
struct SessionExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents the system share sheet for an exported session plan.
struct SessionShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
