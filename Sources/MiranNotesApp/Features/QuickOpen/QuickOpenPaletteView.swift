import SwiftUI

/// Centered quick-open palette (⌘P): type to jump to any note (title/path/body ranked like vault
/// search); empty query shows pinned notes then recents. Return opens, arrows move, Esc closes.
struct QuickOpenPaletteView: View {
    @Bindable var model: AppModel
    @FocusState private var isQueryFocused: Bool

    private var quickOpen: QuickOpenModel { model.quickOpen }

    var body: some View {
        if quickOpen.isPresented {
            ZStack(alignment: .top) {
                // Click-away backdrop.
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture { quickOpen.dismiss() }

                palette
                    .padding(.top, 120)
            }
            .transition(.opacity)
        }
    }

    private var palette: some View {
        let results = model.quickOpenResults(query: quickOpen.query)
        let highlighted = min(quickOpen.highlightedIndex, max(0, results.count - 1))
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Jump to note…", comment: "Quick open: field placeholder"), text: Bindable(quickOpen).query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isQueryFocused)
                    .onSubmit {
                        if results.indices.contains(highlighted) {
                            model.openQuickOpenResult(results[highlighted])
                        }
                    }
                    .onKeyPress(.downArrow) {
                        quickOpen.highlightedIndex = min(results.count - 1, highlighted + 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        quickOpen.highlightedIndex = max(0, highlighted - 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        quickOpen.dismiss()
                        return .handled
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result, isHighlighted: index == highlighted)
                                .onTapGesture { model.openQuickOpenResult(result) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            } else if !quickOpen.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                Text("No matching notes")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 24, y: 8)
        .onAppear { isQueryFocused = true }
        .onChange(of: quickOpen.query) { _, _ in
            quickOpen.highlightedIndex = 0
        }
    }

    @ViewBuilder
    private func resultRow(_ result: QuickOpenResult, isHighlighted: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: sectionIcon(result.section))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(result.snippet ?? result.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    private func sectionIcon(_ section: QuickOpenResult.Section) -> String {
        switch section {
        case .pinned: "pin.fill"
        case .recent: "clock"
        case .match: "doc.text"
        }
    }
}
