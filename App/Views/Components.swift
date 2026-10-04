import SwiftUI

struct StatusDetail: View {
    let title: String
    let value: String
    var symbol: String = "info.circle"

    var body: some View {
        LabeledContent {
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(Color("SecondaryText"))
        } label: {
            Label(title, systemImage: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InformationCard: View {
    let title: String
    let message: String
    var symbol: String = "info.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Color("SecondaryText"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

func displayedDate(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet"
}


/// Keep app-owned section headings readable over both grouped and glass-backed content.
struct ReadableSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title).foregroundStyle(Color("SecondaryText"))
        }
    }
}

/// A wrapping alternative to compact native pickers at accessibility text sizes.
struct AccessibleChoice: View {
    let title: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.frame(minHeight: 44)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
