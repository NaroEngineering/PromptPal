//
//  ContentView.swift
//  PromptPal
//
//  Created by Max Caro on 12/6/25.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Helpers

fileprivate func formatTokenCount(_ tokens: Int) -> String {
    if tokens >= 10_000 {
        let value = Double(tokens) / 1000.0
        return String(format: "~%.2fk", value)
    } else if tokens >= 1_000 {
        let value = Double(tokens) / 1000.0
        return String(format: "~%.1fk", value)
    } else {
        return "\(tokens)"
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var model = PromptPalModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, chooseFolder: chooseFolder)
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
        } detail: {
            MainPanelView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 600)
    }

    // MARK: - Folder Picker

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            model.loadFolder(at: url)
        }
    }
}

// MARK: - Sidebar (File Tree)

struct SidebarView: View {
    @ObservedObject var model: PromptPalModel
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose Folder…") {
                    chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Spacer()
            }

            if let url = model.rootURL {
                Text(url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Select All") {
                    model.setAllSelected(true)
                }
                .disabled(model.nodes.isEmpty)

                Button("Clear") {
                    model.setAllSelected(false)
                }
                .disabled(model.nodes.isEmpty)
            }
            .buttonStyle(.borderless)

            Divider()

            if model.nodes.isEmpty {
                Spacer()
                Text("Pick a folder to see its files.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        OutlineGroup(model.nodes, children: \.children) { node in
                            FileRowView(
                                node: node,
                                onToggle: { node, isOn in
                                    model.setSelection(for: node, isSelected: isOn)
                                }
                            )
                        }
                        .padding(.leading, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.06))
                )
            }
        }
        .padding()
    }
}

// MARK: - File Row

struct FileRowView: View {
    @ObservedObject var node: FileNode
    let onToggle: (FileNode, Bool) -> Void

    var body: some View {
        HStack {
            Toggle(
                isOn: Binding(
                    get: { node.isSelected },
                    set: { newValue in
                        onToggle(node, newValue)
                    }
                )
            ) {
                Label {
                    Text(node.name)
                        .font(node.isDirectory ? .headline : .body)
                } icon: {
                    Image(systemName: node.isDirectory ? "folder" : "doc.plaintext")
                }
            }
            .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Right Panel (Buttons + optional instructions + preview)

struct MainPanelView: View {
    @ObservedObject var model: PromptPalModel
    @State private var showInstructions = false

    private var hasAnythingToSend: Bool {
        !model.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || model.selectedFilesCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Top actions + file count
            HStack(spacing: 8) {
                Button {
                    model.rebuildPreview()
                } label: {
                    if model.isBuildingPrompt {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Building…")
                        }
                    } else {
                        Text("Generate Preview")
                    }
                }
                .disabled(!hasAnythingToSend || model.isBuildingPrompt)

                Button("Copy Prompt") {
                    model.copyPromptToPasteboard()
                }
                // One click: this will build & copy, even if preview is empty
                .disabled(!hasAnythingToSend || model.isBuildingPrompt)

                Spacer()

                Text("\(model.selectedFilesCount) file\(model.selectedFilesCount == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Optional instructions, collapsed by default
            DisclosureGroup(isExpanded: $showInstructions) {
                TextEditor(text: $model.instructions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.25))
                    )
            } label: {
                HStack {
                    Text("Instructions (optional)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }

            Text("Paste the generated prompt into your chat model (ChatGPT, Claude, etc.).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            // Prompt preview area
            PromptPreviewView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
    }
}

// MARK: - Prompt Preview Column

struct PromptPreviewView: View {
    @ObservedObject var model: PromptPalModel
    @State private var showTokenDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Prompt Preview")
                    .font(.headline)

                Spacer()

                if model.isBuildingPrompt {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Building…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Selected files: \(model.selectedFilesCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let tokens = model.estimatedTokenCount
                        Text("Estimated tokens: \(formatTokenCount(tokens))")
                            .font(.caption)
                            .foregroundStyle(tokens > 32_000 ? .red : .secondary)
                    }
                }
            }

            // Token summary / per-file tokens
            if model.selectedFilesCount > 0 {
                tokenSummaryCard
            }

            Divider()

            // Scrollable prompt preview
            Group {
                if model.promptPreview.isEmpty {
                    Text("Click “Copy Prompt” or “Generate Preview” to build the prompt.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    ScrollView {
                        Text(model.promptPreview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.25))
                    )
                }
            }
        }
    }

    private var tokenSummaryCard: some View {
        let fileTokenTotal = model.estimatedFileTokenTotal

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Token summary")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(formatTokenCount(fileTokenTotal)) tokens in files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTokenDetails.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showTokenDetails ? 0 : -90))
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showTokenDetails ? "Hide per-file token estimates" : "Show per-file token estimates")
            }

            if showTokenDetails {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.fileTokenStats) { stat in
                            HStack {
                                Text(model.relativePath(for: stat.node))
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(formatTokenCount(stat.tokenEstimate))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.06))
        )
    }
}

// MARK: - Model

final class PromptPalModel: ObservableObject {
    @Published var rootURL: URL?
    @Published var nodes: [FileNode] = []
    @Published var instructions: String = ""
    @Published var promptPreview: String = ""

    // Used for disabling buttons / showing spinners
    @Published var isBuildingPrompt: Bool = false

    // Dummy to force SwiftUI to refresh when selection changes
    @Published private var selectionVersion: Int = 0

    // MARK: File tree loading

    func loadFolder(at url: URL) {
        rootURL = url
        nodes = buildNodes(for: url)
        promptPreview = ""
        selectionVersion = 0
    }

    private func buildNodes(for directory: URL) -> [FileNode] {
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Collect (url, isDirectory) so we can sort directories before files.
        var entries: [(url: URL, isDirectory: Bool)] = []
        for url in items {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false
            entries.append((url, isDir))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                // Directories first
                return lhs.isDirectory && !rhs.isDirectory
            } else {
                return lhs.url.lastPathComponent.lowercased() < rhs.url.lastPathComponent.lowercased()
            }
        }

        return entries.map { entry in
            if entry.isDirectory {
                let children = buildNodes(for: entry.url)
                return FileNode(url: entry.url, isDirectory: true, children: children)
            } else {
                return FileNode(url: entry.url, isDirectory: false)
            }
        }
    }

    // MARK: Selection helpers

    func setAllSelected(_ value: Bool) {
        nodes.forEach { $0.setSelectedRecursively(value) }
        selectionVersion &+= 1
    }

    func setSelection(for node: FileNode, isSelected: Bool) {
        node.setSelectedRecursively(isSelected)
        selectionVersion &+= 1
    }

    private var selectedFiles: [FileNode] {
        nodes.flatMap { $0.collectSelectedFiles() }
    }

    var selectedFilesCount: Int {
        selectedFiles.count
    }

    // MARK: Prompt building

    func rebuildPreview() {
        buildPrompt(applyToPasteboard: false)
    }

    /// One-click: builds the prompt from the latest files and copies it.
    func copyPromptToPasteboard() {
        buildPrompt(applyToPasteboard: true)
    }

    /// Shared builder used by both Generate Preview and Copy Prompt.
    private func buildPrompt(applyToPasteboard: Bool) {
        // Snapshot state on the main thread
        let instructionsSnapshot = instructions
        let trimmedInstructions = instructionsSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURLSnapshot = rootURL
        let nodesSnapshot = nodes
        let selectedFilesSnapshot = selectedFiles

        // Nothing to send
        guard !trimmedInstructions.isEmpty || !selectedFilesSnapshot.isEmpty else {
            if !applyToPasteboard {
                promptPreview = ""
            }
            return
        }

        isBuildingPrompt = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let prompt = self.buildPrompt(
                instructions: instructionsSnapshot,
                rootURL: rootURLSnapshot,
                nodesSnapshot: nodesSnapshot,
                selectedFilesSnapshot: selectedFilesSnapshot
            )

            DispatchQueue.main.async {
                self.promptPreview = prompt

                if applyToPasteboard {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(prompt, forType: .string)
                }

                self.isBuildingPrompt = false
            }
        }
    }

    private func buildPrompt(
        instructions: String,
        rootURL: URL?,
        nodesSnapshot: [FileNode],
        selectedFilesSnapshot: [FileNode]
    ) -> String {
        var sections: [String] = []

        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFiles = !selectedFilesSnapshot.isEmpty

        if trimmedInstructions.isEmpty && !hasFiles {
            return ""
        }

        if !trimmedInstructions.isEmpty {
            sections.append(trimmedInstructions)
        }

        if let rootURL {
            sections.append(buildFileMapSection(rootURL: rootURL, nodes: nodesSnapshot))
        }

        if hasFiles {
            sections.append(buildFileContentsSection(files: selectedFilesSnapshot))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - <file_map> section

    private func buildFileMapSection(rootURL: URL, nodes: [FileNode]) -> String {
        var lines: [String] = []
        lines.append(rootURL.path)

        appendTree(nodes, prefix: "", into: &lines)

        lines.append("")
        lines.append("(* denotes selected files)")
        lines.append("(+ denotes code-map available)")

        return "<file_map>\n" + lines.joined(separator: "\n") + "\n</file_map>"
    }

    private func appendTree(_ nodes: [FileNode], prefix: String, into lines: inout [String]) {
        for node in nodes {
            // Skip directories that have no file descendants at all
            if node.isDirectory && !node.hasAnyFileDescendant() {
                continue
            }

            let visibleChildren = node.children ?? []
            let siblings = nodes.filter { !$0.isDirectory || $0.hasAnyFileDescendant() }
            guard let index = siblings.firstIndex(where: { $0.id == node.id }) else { continue }
            let isLast = index == siblings.count - 1

            let connector = isLast ? "└── " : "├── "
            let childPrefix = prefix + (isLast ? "    " : "│   ")

            var label = node.name

            if node.isSelected && !node.isDirectory {
                label += " *"
            }

            if codeMapAvailable(for: node) && !node.isDirectory {
                label += " +"
            }

            lines.append(prefix + connector + label)

            if !visibleChildren.isEmpty {
                appendTree(visibleChildren, prefix: childPrefix, into: &lines)
            }
        }
    }

    private func codeMapAvailable(for node: FileNode) -> Bool {
        guard !node.isDirectory else { return false }
        let ext = node.url.pathExtension.lowercased()
        // Match their behavior: only Swift source files get "+"
        switch ext {
        case "swift":
            return true
        default:
            return false
        }
    }

    // MARK: - <file_contents> section

    private func buildFileContentsSection(files: [FileNode]) -> String {
        guard !files.isEmpty else {
            return "<file_contents>\n</file_contents>"
        }

        let parts = files.map { node -> String in
            let path = node.url.path
            let ext = node.url.pathExtension.lowercased()

            let language: String
            switch ext {
            case "swift": language = "swift"
            case "json": language = "json"
            case "plist": language = "plist"
            case "pbxproj": language = "pbxproj"
            case "xcworkspacedata": language = "xcworkspacedata"
            case "xcuserstate": language = "xcuserstate"
            default: language = ""
            }

            let fenceStart = language.isEmpty ? "```" : "```\(language)"

            return """
            File: \(path)
            \(fenceStart)
            \(node.loadContent())
            ```
            """
        }

        return "<file_contents>\n" + parts.joined(separator: "\n\n") + "\n</file_contents>"
    }

    // MARK: - Token utilities

    struct FileTokenStat: Identifiable {
        let id = UUID()
        let node: FileNode
        let tokenEstimate: Int
    }

    var fileTokenStats: [FileTokenStat] {
        let files = selectedFiles
        return files.map { node in
            let content = node.loadContent()
            let tokens = max(1, content.count / 4)
            return FileTokenStat(node: node, tokenEstimate: tokens)
        }
    }

    var estimatedFileTokenTotal: Int {
        fileTokenStats.reduce(0) { $0 + $1.tokenEstimate }
    }

    func relativePath(for node: FileNode) -> String {
        guard let rootURL = rootURL else {
            return node.url.lastPathComponent
        }

        let rootPath = rootURL.path
        let fullPath = node.url.path

        if fullPath.hasPrefix(rootPath) {
            let index = fullPath.index(fullPath.startIndex, offsetBy: rootPath.count)
            var relative = String(fullPath[index...])
            if relative.hasPrefix("/") {
                relative.removeFirst()
            }
            if relative.isEmpty {
                return node.name
            } else {
                return relative
            }
        } else {
            return node.url.lastPathComponent
        }
    }

    // MARK: - Overall token estimate (full prompt)

    var estimatedTokenCount: Int {
        guard !promptPreview.isEmpty else { return 0 }
        // Very rough heuristic: ~4 characters per token on average
        return max(1, promptPreview.count / 4)
    }
}

// MARK: - File Node

final class FileNode: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool

    // Optional children so OutlineGroup can use KeyPath<FileNode, [FileNode]?>
    @Published var children: [FileNode]?
    @Published var isSelected: Bool

    private var cachedContent: String?
    private var cachedModificationDate: Date?

    init(url: URL, isDirectory: Bool, children: [FileNode]? = nil, isSelected: Bool = false) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
        self.isSelected = isSelected
    }

    func setSelectedRecursively(_ value: Bool) {
        isSelected = value
        if isDirectory, let children {
            children.forEach { $0.setSelectedRecursively(value) }
        }
    }

    func collectSelectedFiles() -> [FileNode] {
        if isDirectory {
            return (children ?? []).flatMap { $0.collectSelectedFiles() }
        } else if isSelected {
            return [self]
        } else {
            return []
        }
    }

    /// Loads file content, re-reading from disk only when the file actually changed.
    func loadContent() -> String {
        let path = url.path
        let fm = FileManager.default

        var currentModDate: Date? = nil
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let mod = attrs[.modificationDate] as? Date {
            currentModDate = mod
        }

        if let cachedContent,
           let cachedModificationDate,
           let currentModDate,
           cachedModificationDate == currentModDate {
            return cachedContent
        }

        let text: String
        if let str = try? String(contentsOfFile: path, encoding: .utf8) {
            text = str
        } else if let str = try? String(contentsOf: url, encoding: .utf8) {
            text = str
        } else {
            text = "[Binary file]"
        }

        cachedContent = text
        cachedModificationDate = currentModDate
        return text
    }

    /// Returns true if this node has any (non-directory) file in its subtree.
    func hasAnyFileDescendant() -> Bool {
        if !isDirectory {
            return true
        }
        return (children ?? []).contains { $0.hasAnyFileDescendant() }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
