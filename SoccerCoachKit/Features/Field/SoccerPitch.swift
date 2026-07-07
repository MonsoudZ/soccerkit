import SwiftUI

enum BoardTool: String, CaseIterable, Identifiable {
    case player = "Player"
    case opponent = "Opposition"
    case cone = "Cone"
    case zone = "Zone"
    case line = "Line"
    case erase = "Erase"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .player: return "person.crop.circle.fill"
        case .opponent: return "circle.hexagongrid.circle.fill"
        case .cone: return "triangle.fill"
        case .zone: return "square.dashed"
        case .line: return "arrow.up.right"
        case .erase: return "eraser.fill"
        }
    }
}

struct SoccerPitch: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let line = Color.white.opacity(0.9)

            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.46, blue: 0.22), Color(red: 0.04, green: 0.36, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.045) : Color.clear)
                    }
                }

                Rectangle()
                    .stroke(line, lineWidth: 3)
                    .padding(Spacing.md)

                Path { path in
                    path.move(to: CGPoint(x: 8, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width - 8, y: size.height / 2))
                }
                .stroke(line, lineWidth: 2)

                Circle()
                    .stroke(line, lineWidth: 2)
                    .frame(width: size.width * 0.26, height: size.width * 0.26)

                penaltyBox(atTop: true, size: size)
                    .stroke(line, lineWidth: 2)

                penaltyBox(atTop: false, size: size)
                    .stroke(line, lineWidth: 2)

                goalBox(atTop: true, size: size)
                    .stroke(line, lineWidth: 2)

                goalBox(atTop: false, size: size)
                    .stroke(line, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        }
    }

    private func penaltyBox(atTop: Bool, size: CGSize) -> Path {
        Path { path in
            let width = size.width * 0.62
            let height = size.height * 0.16
            let x = (size.width - width) / 2
            let y = atTop ? 8 : size.height - height - 8
            path.addRect(CGRect(x: x, y: y, width: width, height: height))
        }
    }

    private func goalBox(atTop: Bool, size: CGSize) -> Path {
        Path { path in
            let width = size.width * 0.32
            let height = size.height * 0.065
            let x = (size.width - width) / 2
            let y = atTop ? 8 : size.height - height - 8
            path.addRect(CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

struct ConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
