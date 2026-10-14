import SwiftUI
import AppKit

struct TwitterChecklistView: View {
    @Binding var text: String
    let colorScheme: ColorScheme
    var onClose: () -> Void

    @ObservedObject private var manager = ChecklistManager.shared

    @State private var sidebarWidth: CGFloat = 350
    @State private var isDraggingMover: Bool = false
    @State private var showStrategyDropdown: Bool = false
    @State private var showManageStrategiesSheet: Bool = false
    @State private var showAddRequirementSheet: Bool = false
    @State private var addRequirementPreselectedTag: String = "Hook"
    @State private var editingRequirement: ChecklistRequirement? = nil
    @State private var didCopyPost: Bool = false
    @State private var copiedTemplateId: UUID? = nil
    @State private var collapsedCategories: Set<String> = []
    @State private var tagScrollIndex: Int = 0
    @State private var isHoveringScrollLeft: Bool = false
    @State private var isHoveringScrollRight: Bool = false

    // Colors matching Freewrite
    private var bgPrimary: Color {
        colorScheme == .light ? Color.white : Color.black
    }
    private var bgSecondary: Color {
        colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(white: 0.16)
    }
    private var bgCard: Color {
        colorScheme == .light ? Color.white : Color(white: 0.12)
    }
    private var borderColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
    }
    private var textPrimary: Color {
        colorScheme == .light ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.92, green: 0.92, blue: 0.92)
    }
    private var textSecondary: Color {
        colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
    }
    private var accentBlue: Color {
        Color(red: 0.11, green: 0.53, blue: 0.98)
    }

    // Twitter 280 limits
    private let standardLimit = 280
    private var charCount: Int { text.count }
    private var remainingChars: Int { standardLimit - charCount }

    private var charProgressFraction: Double {
        min(Double(charCount) / Double(standardLimit), 1.0)
    }

    private var charProgressColor: Color {
        if charCount > standardLimit { return .red }
        if charCount > standardLimit - 20 { return .orange }
        return accentBlue
    }

    // Smart heuristics
    private var detectedHook: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
    }

    private var hasReceiptsOrMetrics: Bool {
        let pattern = "\\b\\d+(\\.\\d+)?(%|\\$|k|M|m|x|hrs|days|years)?\\b"
        let hasNumber = text.range(of: pattern, options: .regularExpression) != nil
        let hasLink = text.contains("http://") || text.contains("https://")
        return hasNumber || hasLink
    }

    // Canonical category ordering
    private let canonicalTags = ["Hook", "Writing", "Implementing", "CTA"]

    private var orderedStrategyTags: [String] {
        guard let strat = manager.activeStrategy else { return [] }
        var foundTags = Set(strat.items.map { $0.tag })
        var ordered: [String] = []
        for tag in canonicalTags {
            if let match = foundTags.first(where: { $0.lowercased() == tag.lowercased() }) {
                ordered.append(match)
                foundTags.remove(match)
            }
        }
        ordered.append(contentsOf: foundTags.sorted())
        return ordered
    }

    // Available tags for the active strategy (including "All")
    private var availableTags: [String] {
        ["All"] + orderedStrategyTags
    }

    private var completedCount: Int {
        guard let strat = manager.activeStrategy else { return 0 }
        return strat.items.filter { manager.isItemChecked($0.id) }.count
    }

    private var totalCount: Int {
        manager.activeStrategy?.items.count ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Mover Handle / Slider
            moverHandleBar

            // Main Checklist Content
            VStack(spacing: 0) {
                // Top Header: Strategy Dropdown + Manage + Close
                topHeaderBar

                Divider()

                // Category Tag Filter Horizontal Scroller
                tagFilterScroller

                Divider()

                // Live Checklist Requirement Items (Grouped by Category)
                itemsScrollView

                Divider()

                // Smart Heuristics & Bottom Bar
                bottomActionBar
            }
            .frame(width: sidebarWidth)
            .background(bgPrimary)
        }
        .sheet(isPresented: $showManageStrategiesSheet) {
            ManageStrategiesModal(colorScheme: colorScheme)
        }
        .sheet(isPresented: $showAddRequirementSheet) {
            AddRequirementModal(preselectedTag: addRequirementPreselectedTag, colorScheme: colorScheme)
        }
        .sheet(item: $editingRequirement) { item in
            EditRequirementModal(item: item, colorScheme: colorScheme)
        }
    }

    // MARK: - Mover Handle / Resizer
    private var moverHandleBar: some View {
        ZStack {
            Rectangle()
                .fill(isDraggingMover ? accentBlue.opacity(0.3) : borderColor)
                .frame(width: 5)

            // 6-dot grip indicator
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 2) {
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 2, height: 2)
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 2, height: 2)
                    }
                }
            }
            .frame(width: 12, height: 32)
            .background(bgPrimary)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderColor, lineWidth: 0.5))
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .cursorResizeLeftRight()
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { val in
                    isDraggingMover = true
                    let newWidth = sidebarWidth - val.translation.width
                    sidebarWidth = min(max(newWidth, 290), 580)
                }
                .onEnded { _ in
                    isDraggingMover = false
                }
        )
    }

    // MARK: - Top Header Bar (Dropdown + Manage + Close)
    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            // Strategy Dropdown
            Button(action: {
                showStrategyDropdown.toggle()
            }) {
                HStack(spacing: 6) {
                    if let active = manager.activeStrategy {
                        Text(active.emoji)
                            .font(.system(size: 15))
                        Text(active.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textPrimary)
                            .lineLimit(1)
                    } else {
                        Text("Select Strategy")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textPrimary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bgSecondary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showStrategyDropdown, arrowEdge: .bottom) {
                strategyDropdownPopover
            }

            Spacer()

            // Completion badge
            Text("\(completedCount)/\(totalCount)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(completedCount == totalCount && totalCount > 0 ? Color.green : textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(bgSecondary)
                .cornerRadius(4)

            // Manage Strategies button
            Button(action: {
                showManageStrategiesSheet = true
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(textSecondary)
                    .frame(width: 24, height: 24)
                    .background(bgSecondary)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Manage Strategies")

            // Close button
            Button(action: {
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textSecondary)
                    .frame(width: 24, height: 24)
                    .background(bgSecondary)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Hide Checklist")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Strategy Dropdown Popover
    private var strategyDropdownPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Select Strategy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textSecondary)
                Spacer()
                Button(action: {
                    showStrategyDropdown = false
                    showManageStrategiesSheet = true
                }) {
                    Text("+ Manage")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(manager.strategies) { strat in
                        let isSelected = strat.id == manager.activeStrategy?.id
                        Button(action: {
                            manager.activeStrategyId = strat.id
                            showStrategyDropdown = false
                        }) {
                            HStack(spacing: 8) {
                                Text(strat.emoji)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(strat.name)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                        .foregroundColor(isSelected ? accentBlue : textPrimary)
                                    Text(strat.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(accentBlue)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isSelected ? accentBlue.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 270)
        .background(bgPrimary)
    }

    // MARK: - Tag Filter Horizontal Scroller with Mouse Controls
    private var tagFilterScroller: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 3) {
                // Scroll Left Button (<)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tagScrollIndex = max(0, tagScrollIndex - 1)
                        if availableTags.indices.contains(tagScrollIndex) {
                            proxy.scrollTo(availableTags[tagScrollIndex], anchor: .leading)
                        }
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tagScrollIndex > 0 ? textPrimary : textSecondary.opacity(0.35))
                        .frame(width: 18, height: 26)
                        .background(isHoveringScrollLeft ? bgSecondary : bgSecondary.opacity(0.4))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringScrollLeft = hovering
                }
                .help("Scroll left")

                // Main Horizontal Scroller (Mouse Wheel Enabled & Shows Scroller)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 6) {
                        ForEach(Array(availableTags.enumerated()), id: \.element) { index, tag in
                            let isSelected = manager.selectedTagFilter.lowercased() == tag.lowercased()
                            let meta = categoryMeta(for: tag)
                            let count = countForTag(tag)

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    manager.selectedTagFilter = tag
                                    tagScrollIndex = index
                                    proxy.scrollTo(tag, anchor: .center)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if tag != "All" {
                                        Text(meta.emoji)
                                            .font(.system(size: 10))
                                    }
                                    Text(tag == "All" ? "All" : meta.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    Text("(\(count))")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .opacity(0.7)
                                }
                                .foregroundColor(isSelected ? .white : textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(isSelected ? meta.color : bgSecondary)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .id(tag)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                    .background(HorizontalMouseWheelScroller())
                }

                // Scroll Right Button (>)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tagScrollIndex = min(availableTags.count - 1, tagScrollIndex + 1)
                        if availableTags.indices.contains(tagScrollIndex) {
                            proxy.scrollTo(availableTags[tagScrollIndex], anchor: .trailing)
                        }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tagScrollIndex < availableTags.count - 1 ? textPrimary : textSecondary.opacity(0.35))
                        .frame(width: 18, height: 26)
                        .background(isHoveringScrollRight ? bgSecondary : bgSecondary.opacity(0.4))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringScrollRight = hovering
                }
                .help("Scroll right")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(bgSecondary.opacity(0.4))
        }
    }

    private func countForTag(_ tag: String) -> Int {
        guard let strat = manager.activeStrategy else { return 0 }
        if tag == "All" {
            return strat.items.count
        }
        return strat.items.filter { $0.tag.lowercased() == tag.lowercased() }.count
    }

    // MARK: - Checklist Items List (Grouped by Category)
    private var itemsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if manager.selectedTagFilter == "All" {
                    // Show all categories in canonical groups
                    ForEach(orderedStrategyTags, id: \.self) { tag in
                        let itemsInTag = (manager.activeStrategy?.items ?? []).filter { $0.tag.lowercased() == tag.lowercased() }
                        if !itemsInTag.isEmpty {
                            categorySectionView(tag: tag, items: itemsInTag)
                        }
                    }
                } else {
                    // Show single selected category
                    let tag = manager.selectedTagFilter
                    let itemsInTag = (manager.activeStrategy?.items ?? []).filter { $0.tag.lowercased() == tag.lowercased() }
                    categorySectionView(tag: tag, items: itemsInTag)
                }

                // Global Add Requirement Button
                Button(action: {
                    addRequirementPreselectedTag = manager.selectedTagFilter == "All" ? "Hook" : manager.selectedTagFilter
                    showAddRequirementSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                        Text("Add Custom Requirement")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(accentBlue.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(accentBlue.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(12)
        }
    }

    // MARK: - Category Section View
    @ViewBuilder
    private func categorySectionView(tag: String, items: [ChecklistRequirement]) -> some View {
        let meta = categoryMeta(for: tag)
        let isCollapsed = collapsedCategories.contains(tag.lowercased())
        let completedInCat = items.filter { manager.isItemChecked($0.id) }.count

        VStack(spacing: 6) {
            // Category Section Header
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isCollapsed {
                            collapsedCategories.remove(tag.lowercased())
                        } else {
                            collapsedCategories.insert(tag.lowercased())
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(textSecondary)
                            .frame(width: 12)

                        Text(meta.emoji)
                            .font(.system(size: 13))

                        Text(meta.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(textPrimary)

                        Text("\(completedInCat)/\(items.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(completedInCat == items.count ? Color.green : textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(meta.color.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Quick Add for this category
                Button(action: {
                    addRequirementPreselectedTag = tag
                    showAddRequirementSheet = true
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                        Text("Add")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(meta.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(meta.color.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Add a new \(meta.displayName) type")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // Items List (if not collapsed)
            if !isCollapsed {
                VStack(spacing: 7) {
                    ForEach(items) { item in
                        requirementCard(item: item, meta: meta)
                    }
                }
            }
        }
        .padding(8)
        .background(bgSecondary.opacity(0.25))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }


    private func insertSnippetIntoEditor(_ snippet: String, itemId: UUID) {
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)

        // Insert snippet into text editor
        let sep: String
        let newline = "\n"
        let doubleNewline = "\n\n"
        if text.isEmpty {
            sep = ""
        } else if text.hasSuffix(doubleNewline) {
            sep = ""
        } else if text.hasSuffix(newline) {
            sep = newline
        } else {
            sep = doubleNewline
        }
        text += sep + snippet

        // Auto check the requirement
        if !manager.isItemChecked(itemId) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                manager.toggleCheck(itemId: itemId)
            }
        }

        // Visual flash feedback
        copiedTemplateId = itemId
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedTemplateId == itemId {
                copiedTemplateId = nil
            }
        }
    }

    // MARK: - Requirement Card
    @ViewBuilder
    private func requirementCard(item: ChecklistRequirement, meta: (displayName: String, emoji: String, color: Color)) -> some View {
        let isChecked = manager.isItemChecked(item.id)

        ZStack(alignment: .topTrailing) {
            // Card Content
            HStack(alignment: .top, spacing: 10) {
                // Interactive Checkbox
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        manager.toggleCheck(itemId: item.id)
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isChecked ? Color.green : textSecondary.opacity(0.6), lineWidth: 1.5)
                            .background(isChecked ? Color.green : Color.clear)
                            .cornerRadius(4)
                            .frame(width: 18, height: 18)

                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 1)

                // Title & Guidance & Template
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isChecked ? textSecondary : textPrimary)
                        .strikethrough(isChecked, color: textSecondary)
                        .lineLimit(2)
                        .padding(.trailing, 26) // Leave room for chevron menu

                    if !item.guidance.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text(item.guidance)
                                .font(.system(size: 10))
                                .foregroundColor(textSecondary)
                                .lineSpacing(2)

                            // If no formula template exists, allow copying guidance directly into editor
                            if item.template == nil || item.template!.isEmpty {
                                Spacer()
                                Button(action: {
                                    insertSnippetIntoEditor(item.guidance, itemId: item.id)
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: copiedTemplateId == item.id ? "checkmark" : "arrow.left.circle")
                                            .font(.system(size: 8))
                                        Text(copiedTemplateId == item.id ? "Inserted" : "Use")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(copiedTemplateId == item.id ? Color.green : textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(bgSecondary)
                                    .cornerRadius(3)
                                }
                                .buttonStyle(.plain)
                                .help("Insert guidance into editor and check")
                            }
                        }
                    }

                    // Visual Template / Example Formula Box (Copy & Insert into editor)
                    if let template = item.template, !template.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 9))
                                .foregroundColor(meta.color)
                                .padding(.top, 1)

                            Text(template)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(textPrimary)
                                .lineLimit(3)

                            Spacer()

                            Button(action: {
                                insertSnippetIntoEditor(template, itemId: item.id)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: copiedTemplateId == item.id ? "checkmark" : "arrow.left.circle")
                                        .font(.system(size: 8))
                                    Text(copiedTemplateId == item.id ? "Inserted" : "Copy")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(copiedTemplateId == item.id ? Color.green : textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(bgSecondary)
                                .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .help("Insert into editor, copy to clipboard, and check")
                        }
                        .padding(6)
                        .background(bgSecondary.opacity(0.6))
                        .cornerRadius(4)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        manager.toggleCheck(itemId: item.id)
                    }
                }
            }
            .padding(10)
            .background(bgCard)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isChecked ? Color.green.opacity(0.3) : borderColor, lineWidth: 0.8)
            )

            // ONLY Dropdown Icon (User request)
            Menu {
                if let template = item.template, !template.isEmpty {
                    Button(action: {
                        insertSnippetIntoEditor(template, itemId: item.id)
                    }) {
                        Label("Insert & Check Formula", systemImage: "arrow.left.circle")
                    }
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(template, forType: .string)
                    }) {
                        Label("Copy Formula Only", systemImage: "doc.on.doc")
                    }
                }
                Button(action: {
                    insertSnippetIntoEditor(item.guidance, itemId: item.id)
                }) {
                    Label("Insert & Check Guidance", systemImage: "text.quote")
                }
                Divider()
                Button("Edit Requirement") {
                    editingRequirement = item
                }
                Button("Delete Requirement", role: .destructive) {
                    if let active = manager.activeStrategy {
                        manager.deleteRequirement(strategyId: active.id, itemId: item.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(textSecondary)
                    .frame(width: 22, height: 22)
                    .background(bgSecondary.opacity(0.6))
                    .cornerRadius(4)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .zIndex(10)
        }
    }

    private func categoryMeta(for tag: String) -> (displayName: String, emoji: String, color: Color) {
        switch tag.lowercased() {
        case "hook", "hooks":
            return ("Hooks", "🎣", Color.purple)
        case "writing", "body":
            return ("Writing", "✍️", Color.blue)
        case "implementing", "evidence", "implementation":
            return ("Implementing", "🛠️", Color.green)
        case "cta":
            return ("Call to Action", "📣", Color.orange)
        case "tone":
            return ("Tone", "🎨", Color.red)
        case "structure":
            return ("Structure", "📐", Color.indigo)
        default:
            return (tag.capitalized, "📌", textSecondary)
        }
    }

    // MARK: - Smart Heuristics & Bottom Bar
    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            // Heuristic alerts
            if let hook = detectedHook {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.purple)
                    Text("Hook: \"\(hook.prefix(28))\(hook.count > 28 ? "..." : "")\"")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(4)
            }

            if hasReceiptsOrMetrics {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.green)
                    Text("Receipts / Proof verified")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.green)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.08))
                .cornerRadius(4)
            }

            // Controls: Ring + Remaining + Icon-only buttons
            HStack(spacing: 8) {
                // Circular 280 progress indicator
                ZStack {
                    Circle()
                        .stroke(borderColor, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    Circle()
                        .trim(from: 0.0, to: CGFloat(charProgressFraction))
                        .stroke(charProgressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                }

                Text("\(remainingChars)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(remainingChars < 0 ? .red : (remainingChars < 20 ? .orange : textSecondary))

                Spacer()

                // Reset checks button
                Button(action: {
                    manager.resetChecks()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundColor(textSecondary)
                        .frame(width: 28, height: 28)
                        .background(bgSecondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Reset checklist")

                // Copy Clean Post (Icon only)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopyPost = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        didCopyPost = false
                    }
                }) {
                    Image(systemName: didCopyPost ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(didCopyPost ? Color.green : textPrimary)
                        .frame(width: 28, height: 28)
                        .background(bgSecondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(didCopyPost ? "Copied!" : "Copy Post to Clipboard")
                .disabled(text.isEmpty)

                // Post on X (Icon only)
                Button(action: {
                    if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: "https://x.com/intent/post?text=\(encoded)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(accentBlue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Post on X")
                .disabled(text.isEmpty)
            }
        }
        .padding(12)
        .background(bgSecondary.opacity(0.3))
    }
}

// MARK: - Cursor modifier for resizing
extension View {
    func cursorResizeLeftRight() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Redesigned Manage Strategies Modal (Modern, Native Apple Design)
struct ManageStrategiesModal: View {
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ChecklistManager.shared

    @State private var selectedTab: Int = 0 // 0: All Strategies, 1: Add New
    @State private var newName: String = ""
    @State private var newEmoji: String = "🔥"
    @State private var newDesc: String = ""
    @State private var useStarterTemplate: Bool = true
    @State private var showRestoreConfirmation: Bool = false

    private let emojiPresets = ["🔥", "📚", "🚀", "💡", "⚡", "🎯", "🧵", "🧪", "💰", "🏆", "💎", "✍️"]

    private var bgCard: Color {
        colorScheme == .light ? Color.white : Color(white: 0.14)
    }
    private var bgInput: Color {
        colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(white: 0.18)
    }
    private var borderColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modal Top Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Post Strategies")
                        .font(.system(size: 15, weight: .bold))
                    Text("Configure categories, multi-stage rules, and hooks")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Segmented Tab Selector
                Picker("", selection: $selectedTab) {
                    Text("All Strategies (\(manager.strategies.count))").tag(0)
                    Text("+ New Strategy").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            if selectedTab == 0 {
                // Tab 0: List of existing strategies
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(manager.strategies) { strat in
                                HStack(spacing: 12) {
                                    Text(strat.emoji)
                                        .font(.system(size: 24))
                                        .frame(width: 36, height: 36)
                                        .background(bgInput)
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(strat.name)
                                                .font(.system(size: 13, weight: .bold))
                                            if strat.id == manager.activeStrategy?.id {
                                                Text("ACTIVE")
                                                    .font(.system(size: 9, weight: .heavy))
                                                    .foregroundColor(.blue)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.blue.opacity(0.12))
                                                    .cornerRadius(3)
                                            }
                                        }

                                        Text(strat.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)

                                        Text("\(strat.items.count) rules across Hooks, Writing, Implementing, CTA")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.purple)
                                            .padding(.top, 1)
                                    }

                                    Spacer()

                                    if strat.id != manager.activeStrategy?.id {
                                        Button("Select") {
                                            manager.activeStrategyId = strat.id
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                    }

                                    if manager.strategies.count > 1 {
                                        Button(action: {
                                            manager.deleteStrategy(id: strat.id)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(.red.opacity(0.8))
                                                .frame(width: 24, height: 24)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete strategy")
                                    }
                                }
                                .padding(12)
                                .background(bgCard)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(strat.id == manager.activeStrategy?.id ? Color.blue.opacity(0.5) : borderColor, lineWidth: 1)
                                )
                            }
                        }
                        .padding(16)
                    }

                    Divider()

                    // Bottom Bar with Reset to Full Multi-Category Presets
                    HStack {
                        Button(action: {
                            showRestoreConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Restore Full Presets (10 Hooks, Writing, CTA)")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Restore full multi-category presets for all default strategies?", isPresented: $showRestoreConfirmation) {
                            Button("Restore Defaults", role: .destructive) {
                                manager.restoreDefaultStrategies()
                            }
                            Button("Cancel", role: .cancel) {}
                        }

                        Spacer()

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .padding(14)
                    .background(bgInput.opacity(0.4))
                }
            } else {
                // Tab 1: Create New Strategy
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Emoji Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strategy Icon")
                                .font(.system(size: 12, weight: .semibold))
                            HStack(spacing: 8) {
                                ForEach(emojiPresets, id: \.self) { emoji in
                                    Button(action: { newEmoji = emoji }) {
                                        Text(emoji)
                                            .font(.system(size: 18))
                                            .frame(width: 32, height: 32)
                                            .background(newEmoji == emoji ? Color.blue.opacity(0.2) : bgInput)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(newEmoji == emoji ? Color.blue : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Name Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strategy Name")
                                .font(.system(size: 12, weight: .semibold))
                            TextField("e.g. Founder Journey, SaaS Teardown, Hot Debate...", text: $newName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(bgInput)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                        }

                        // Goal / Description Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strategy Purpose / Goal")
                                .font(.system(size: 12, weight: .semibold))
                            TextField("e.g. Build authority through step-by-step technical teardowns", text: $newDesc)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(bgInput)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                        }

                        // Template toggle
                        Toggle(isOn: $useStarterTemplate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include Starter Categories (Hooks, Writing, Implementing, CTA)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Pre-populates full 4-stage multi-category framework")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)

                        // Submit Button
                        Button(action: {
                            guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let items: [ChecklistRequirement]? = useStarterTemplate ? nil : []
                            manager.addStrategy(name: newName, emoji: newEmoji, description: newDesc, initialItems: items)
                            newName = ""
                            newDesc = ""
                            selectedTab = 0
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create Strategy")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 540, height: 480)
        .background(colorScheme == .light ? Color.white : Color(white: 0.11))
    }
}

// MARK: - Redesigned Add Requirement Modal (Clean, Multi-Category UX with Formula Presets)
struct AddRequirementModal: View {
    var preselectedTag: String = "Hook"
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ChecklistManager.shared

    @State private var title: String = ""
    @State private var guidance: String = ""
    @State private var template: String = ""
    @State private var selectedTag: String = "Hook"

    private let tagOptions = [
        ("Hook", "🎣", "Hooks", Color.purple),
        ("Writing", "✍️", "Writing", Color.blue),
        ("Implementing", "🛠️", "Implementing", Color.green),
        ("CTA", "📣", "Call to Action", Color.orange)
    ]

    private var bgInput: Color {
        colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(white: 0.18)
    }
    private var borderColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
    }

    // Curated Library of Presets per Category for Fast Adding
    private var formulaPresets: [(title: String, guidance: String, template: String)] {
        switch selectedTag.lowercased() {
        case "hook":
            return [
                ("The 'X is Dead' Disruptor", "Only declare something dead if you provide a superior alternative immediately.", "[Common practice] is dead. Here is what is replacing it in 2026:"),
                ("The Harsh Truth / Reality Check", "Articulate a widely felt frustration or taboo truth that people hesitate to speak.", "Unpopular opinion: [Hard truth that 90% of people avoid admitting]."),
                ("The Counter-Intuitive Reversal", "Flip standard advice on its head with counter-intuitive logic.", "Doing [common advice] is the exact reason you are failing at [goal]. Do this instead:"),
                ("The 'Stop Doing X' Warning", "Creates intense urgency and loss aversion by calling out an active mistake.", "Stop doing [common behavior] in 2026. It's secretly destroying your [result]."),
                ("The Industry Call-Out", "Breaks the fourth wall and establishes insider authority by exposing industry secrets.", "I'm going to say what most [founders/experts] won't say publicly:"),
                ("The Bold Contrarian Claim", "Contrasts herd mentality with what top 1% practitioners actually do.", "Everyone is hyping [popular trend], but 99% of people are missing the real trap:"),
                ("The Shocking Metric Disconnect", "Use hard contrasting numbers to break mental patterns and create dissonance.", "[90]% of people spend hours on [X]. It only drives [5]% of results. Here is what moves the needle:"),
                ("The Anti-Advice Hook", "Uses personal scar tissue and cautionary framing against bad mainstream guidance.", "The worst advice I ever received was '[popular adage]'. Here is why it cost me:"),
                ("The Paradox / Irony Hook", "Frames the problem as a psychological paradox where trying harder makes things worse.", "The harder you chase [result], the further away it gets. The paradox of [topic]:"),
                ("The Dramatic Prediction", "Forces immediate self-evaluation by setting a ticking clock on obsolete habits.", "In 12 months, [industry/skill] won't look anything like today. If you aren't doing [X], you're already behind:")
            ]
        case "writing":
            return [
                ("Steelman Counter-Argument", "Acknowledge the sensible opposing viewpoint in 1 sentence before debunking it.", "I get why people advocate for [opposing view]. It works if [niche scenario]. But for everyone else:"),
                ("High-Contrast Sentences", "Cut filler words. Alternate 3-word punchy sentences with short explanations.", "Most focus on volume. The best focus on leverage."),
                ("The Isolated 1-Line Truth", "Put your core thesis on its own line surrounded by whitespace for maximum impact.", "If it doesn't hurt your ego a little bit, it's not a real insight."),
                ("Zero-Hedging Tone", "Remove weak phrases like 'I think' or 'maybe'. Speak with grounded conviction.", "Cut 'I think' and 'maybe'. State your thesis directly."),
                ("Tension Before Resolution", "Hold back the full solution until the middle of the post to maximize read-through rate.", "Don't resolve the mystery in the first 2 lines. Keep them reading to line 4.")
            ]
        case "implementing":
            return [
                ("Concrete Receipts & Proof", "Back up controversial claims with real screenshots, benchmarks, or hard numbers.", "Here are the exact numbers from testing this over [timeframe]:"),
                ("3-Step Replacement Playbook", "Don't just criticize the status quo; give a concrete, actionable alternative system.", "Step 1: [Action]\nStep 2: [Action]\nStep 3: [Action]"),
                ("The Boundary Exception Clause", "Explicitly clarify when your take DOES NOT apply to protect against cheap nitpicking.", "(Note: this does not apply if you are [specific scenario].)"),
                ("Before vs After Delta", "Contrast the old flawed way with the new optimized outcome side-by-side.", "Old way: [Effort] -> [Poor result]\nNew way: [Smart effort] -> [10x result]"),
                ("15-Minute Actionable Test", "Give the reader 1 micro-action they can test today to verify your claim themselves.", "Try this for 15 minutes today: [Specific test]. See the difference yourself.")
            ]
        case "cta":
            return [
                ("The Open Debate Question", "Ask an open question that forces readers to pick a side in the comments.", "Where do you stand on this? Agree or disagree? Tell me below."),
                ("The 'Prove Me Wrong' Challenge", "Invites critical minds and experts to engage in constructive debate.", "Change my mind. Tell me where this thesis breaks down in the replies."),
                ("The Bookmark Reality Check", "Remind readers to save/bookmark this post for reference when they face this situation.", "Bookmark this to revisit before you make this costly mistake again."),
                ("The Quote-Tweet Trigger", "Prompt quote tweets to tap into second-degree audiences.", "Quote-tweet this with your most controversial belief on [topic]."),
                ("Unfiltered Follow Prompt", "Convert impressed readers into followers by promising more no-BS insights.", "If you want raw, unfiltered lessons on [topic], follow for daily breakdowns.")
            ]
        default:
            return []
        }
    }

    init(preselectedTag: String = "Hook", colorScheme: ColorScheme) {
        self.preselectedTag = preselectedTag
        self.colorScheme = colorScheme
        _selectedTag = State(initialValue: preselectedTag)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Requirement / Stage Rule")
                        .font(.system(size: 15, weight: .bold))
                    if let active = manager.activeStrategy {
                        Text("Adding to: \(active.emoji) \(active.name)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Category Tag Selector (Visual Pills)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category / Stage")
                            .font(.system(size: 12, weight: .semibold))

                        HStack(spacing: 6) {
                            ForEach(tagOptions, id: \.0) { tag, icon, name, color in
                                let isSelected = selectedTag.lowercased() == tag.lowercased()
                                Button(action: {
                                    selectedTag = tag
                                }) {
                                    HStack(spacing: 4) {
                                        Text(icon)
                                            .font(.system(size: 11))
                                        Text(name)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    }
                                    .foregroundColor(isSelected ? .white : color)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? color : color.opacity(0.12))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Formula Preset Selector Menu (Fast Auto-Fill)
                    if !formulaPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Formula & Technique Presets")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Menu {
                                ForEach(formulaPresets, id: \.title) { preset in
                                    Button(preset.title) {
                                        title = preset.title
                                        guidance = preset.guidance
                                        template = preset.template
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("Pick a \(selectedTag) formula from library...")
                                        .font(.system(size: 11))
                                        .foregroundColor(colorScheme == .light ? .black : .white)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(bgInput)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }

                    // Requirement Title Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rule / Hook Title")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("e.g. The 'Stop Doing X' Warning, Concrete Receipts...", text: $title)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Tip / Guidance Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verification Guidance / Strategy Tip")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("e.g. Creates intense urgency and calls out a common mistake...", text: $guidance)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Formula Template Text Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Example Formula / Template (Optional)")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("Shows visual quote card in checklist")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        TextField("e.g. Stop doing [behavior] in 2026. It's destroying your [result]:", text: $template)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Live Preview Card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live Preview")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(title.isEmpty ? "Rule or Hook Title" : title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(title.isEmpty ? .secondary : (colorScheme == .light ? .black : .white))

                                if !guidance.isEmpty {
                                    Text(guidance)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                if !template.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "quote.opening")
                                            .font(.system(size: 8))
                                            .foregroundColor(.purple)
                                        Text(template)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                    }
                                    .padding(5)
                                    .background(bgInput)
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgInput.opacity(0.5))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Action Buttons
                    HStack(spacing: 10) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .frame(width: 80, height: 32)
                        .background(bgInput)
                        .cornerRadius(6)

                        Spacer()

                        Button(action: {
                            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            if let active = manager.activeStrategy {
                                manager.addRequirement(to: active.id, title: title, guidance: guidance, tag: selectedTag, template: template)
                            }
                            dismiss()
                        }) {
                            Text("Add to Checklist")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 6)
                }
                .padding(18)
            }
        }
        .frame(width: 500, height: 530)
        .background(colorScheme == .light ? Color.white : Color(white: 0.12))
    }
}

// MARK: - Redesigned Edit Requirement Modal
struct EditRequirementModal: View {
    let item: ChecklistRequirement
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ChecklistManager.shared

    @State private var title: String = ""
    @State private var guidance: String = ""
    @State private var template: String = ""
    @State private var selectedTag: String = "Hook"

    private let tagOptions = [
        ("Hook", "🎣", "Hooks", Color.purple),
        ("Writing", "✍️", "Writing", Color.blue),
        ("Implementing", "🛠️", "Implementing", Color.green),
        ("CTA", "📣", "Call to Action", Color.orange)
    ]

    private var bgInput: Color {
        colorScheme == .light ? Color(NSColor.controlBackgroundColor) : Color(white: 0.18)
    }
    private var borderColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
    }

    init(item: ChecklistRequirement, colorScheme: ColorScheme) {
        self.item = item
        self.colorScheme = colorScheme
        _title = State(initialValue: item.title)
        _guidance = State(initialValue: item.guidance)
        _template = State(initialValue: item.template ?? "")
        _selectedTag = State(initialValue: item.tag)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Requirement / Rule")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Category Tag Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category / Stage")
                            .font(.system(size: 12, weight: .semibold))

                        HStack(spacing: 6) {
                            ForEach(tagOptions, id: \.0) { tag, icon, name, color in
                                let isSelected = selectedTag.lowercased() == tag.lowercased()
                                Button(action: {
                                    selectedTag = tag
                                }) {
                                    HStack(spacing: 4) {
                                        Text(icon)
                                            .font(.system(size: 11))
                                        Text(name)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    }
                                    .foregroundColor(isSelected ? .white : color)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? color : color.opacity(0.12))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Requirement Title Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rule / Hook Title")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("Title", text: $title)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Guidance Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verification Guidance / Strategy Tip")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("Guidance", text: $guidance)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Formula Template Text Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Example Formula / Template (Optional)")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("Formula or Template", text: $template)
                            .textFieldStyle(.plain)
                            .padding(9)
                            .background(bgInput)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.8))
                    }

                    // Action Buttons
                    HStack(spacing: 10) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .frame(width: 80, height: 32)
                        .background(bgInput)
                        .cornerRadius(6)

                        Spacer()

                        Button(action: {
                            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            if let active = manager.activeStrategy {
                                manager.updateRequirement(
                                    strategyId: active.id,
                                    itemId: item.id,
                                    title: title,
                                    guidance: guidance,
                                    tag: selectedTag,
                                    template: template
                                )
                            }
                            dismiss()
                        }) {
                            Text("Save Changes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 6)
                }
                .padding(18)
            }
        }
        .frame(width: 480, height: 480)
        .background(colorScheme == .light ? Color.white : Color(white: 0.12))
    }
}


// MARK: - Mouse Wheel Horizontal Scroll Interceptor
struct HorizontalMouseWheelScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WheelHelperView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class WheelHelperView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self = self,
                          let scrollView = self.enclosingScrollView,
                          let window = self.window else {
                        return event
                    }
                    let mouseInWindow = window.mouseLocationOutsideOfEventStream
                    let mouseInView = scrollView.convert(mouseInWindow, from: nil)
                    if scrollView.bounds.contains(mouseInView) {
                        // User is scrolling mouse wheel over this horizontal scroll view
                        if event.scrollingDeltaX == 0 && (event.scrollingDeltaY != 0 || event.deltaY != 0) {
                            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : (event.deltaY * 20.0)
                            let clipView = scrollView.contentView
                            var origin = clipView.bounds.origin
                            origin.x -= delta
                            let maxX = max(0, (scrollView.documentView?.bounds.width ?? 0) - clipView.bounds.width)
                            origin.x = min(max(origin.x, 0), maxX)
                            clipView.scroll(to: origin)
                            scrollView.reflectScrolledClipView(clipView)
                            return nil // Consumed!
                        }
                    }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
