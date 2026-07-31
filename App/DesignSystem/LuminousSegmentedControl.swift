import SwiftUI

/// The app's segmented control, replacing `.pickerStyle(.segmented)` in the sky
/// and browse chrome. The system control's solid-white selection pill is the
/// loudest element on any screen it appears on and speaks a different language
/// than the luminous circle buttons beside it; this one marks the selection with
/// a tinted ring + soft glow over night-ink glass instead.
struct LuminousSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var tint: Color = Theme.accent

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
        .padding(3)
        .glassEffect(.regular.tint(Theme.nightInk.opacity(0.5)), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(_ value: Value, label: String) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(Theme.spring) { selection = value }
        } label: {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(tint.opacity(0.16))
                            .overlay { Capsule().strokeBorder(tint.opacity(0.75), lineWidth: 1) }
                            .shadow(color: tint.opacity(0.4), radius: 7)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var mode = "Sky"
    ZStack {
        Theme.spaceGradient.ignoresSafeArea()
        VStack(spacing: 24) {
            LuminousSegmentedControl(selection: $mode,
                                     options: [("Sky", "Sky"), ("AR", "AR")].map { ($0.0, $0.1) })
                .frame(width: 150)
            LuminousSegmentedControl(selection: $mode,
                                     options: ["The 88", "Asterisms", "Historical", "Cultural"].map { ($0, $0) })
        }
        .padding()
    }
}
