import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.055, blue: 0.075)
    static let card = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let text = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let secondary = Color(red: 0.62, green: 0.67, blue: 0.74)
    static let safe = Color(red: 0.24, green: 0.86, blue: 0.59)
}

struct Principle: Identifiable {
    let id: String
    let badge: String

    static let all: [Principle] = [
        Principle(id: "local", badge: "1"),
        Principle(id: "upload", badge: "2"),
        Principle(id: "store", badge: "3"),
    ]

    var title: String {
        switch id {
        case "local": return L10n.principleLocalTitle
        case "upload": return L10n.principleUploadTitle
        case "store": return L10n.principleStoreTitle
        default: return ""
        }
    }

    var detail: String {
        switch id {
        case "local": return L10n.principleLocalDetail
        case "upload": return L10n.principleUploadDetail
        case "store": return L10n.principleStoreDetail
        default: return ""
        }
    }
}

struct PrincipleRow: View {
    let principle: Principle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(principle.badge)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.background)
                .frame(width: 36, height: 36)
                .background(Theme.safe, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(principle.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text(principle.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
