import SwiftUI

// MARK: - Model Versions View

struct ModelVersionsView: View {
    let modelId: String
    let modelName: String

    @State private var versions: [ModelVersion] = []
    @State private var selectedVersion: ModelVersion?
    @State private var showCreateVersion = false
    @State private var isLoading = true
    @State private var showDeleteConfirmation = false
    @State private var versionToDelete: ModelVersion?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version History")
                        .font(.headline)
                    Text(modelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showCreateVersion = true }) {
                    Label("Create Version", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading versions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if versions.isEmpty {
                EmptyVersionsView(onCreate: { showCreateVersion = true })
            } else {
                HSplitView {
                    // Version timeline
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(versions.reversed()) { version in
                                VersionTimelineRow(
                                    version: version,
                                    isSelected: selectedVersion?.id == version.id,
                                    isFirst: version.id == versions.last?.id,
                                    isLast: version.id == versions.first?.id,
                                    onSelect: { selectedVersion = version },
                                    onSetProduction: { setProduction(version) },
                                    onDelete: {
                                        versionToDelete = version
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                    .frame(minWidth: 300)

                    // Version detail
                    if let version = selectedVersion {
                        VersionDetailView(version: version)
                    } else {
                        PlaceholderDetailView(
                            icon: "clock.arrow.circlepath",
                            title: "Select a Version",
                            subtitle: "Choose a version to view details"
                        )
                    }
                }
            }
        }
        .task {
            await loadVersions()
        }
        .sheet(isPresented: $showCreateVersion) {
            CreateVersionSheet(modelId: modelId, modelName: modelName) { newVersion in
                versions.append(newVersion)
                selectedVersion = newVersion
            }
        }
        .alert("Delete Version", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let version = versionToDelete {
                    deleteVersion(version)
                }
            }
        } message: {
            Text("Are you sure you want to delete version \(versionToDelete?.version ?? "")? This cannot be undone.")
        }
    }

    private func loadVersions() async {
        isLoading = true
        versions = await ModelVersionManager.shared.getVersions(for: modelId)
        if let first = versions.first {
            selectedVersion = first
        }
        isLoading = false
    }

    private func setProduction(_ version: ModelVersion) {
        Task {
            try? await ModelVersionManager.shared.setProduction(versionId: version.id, modelId: modelId)
            await loadVersions()
        }
    }

    private func deleteVersion(_ version: ModelVersion) {
        Task {
            try? await ModelVersionManager.shared.deleteVersion(id: version.id)
            if selectedVersion?.id == version.id {
                selectedVersion = nil
            }
            await loadVersions()
        }
    }
}

// MARK: - Empty Versions View

struct EmptyVersionsView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("No Versions Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Create a version to track model changes and enable rollbacks")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button("Create First Version", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Version Timeline Row

struct VersionTimelineRow: View {
    let version: ModelVersion
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let onSelect: () -> Void
    let onSetProduction: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Timeline indicator
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 20)

                ZStack {
                    Circle()
                        .fill(version.isProduction ? Color.green : Color.accentColor)
                        .frame(width: 14, height: 14)

                    if version.isProduction {
                        Image(systemName: "star.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.white)
                    }
                }

                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 20)
            }
            .frame(width: 20)

            // Version info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("v\(version.version)")
                        .font(.headline)
                        .fontWeight(.semibold)

                    if version.isProduction {
                        Label("Production", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text(version.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Metrics
                HStack(spacing: 12) {
                    if let accuracy = version.accuracy {
                        Label(String(format: "%.1f%%", accuracy * 100), systemImage: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.green)
                    }
                    if let loss = version.loss {
                        Label(String(format: "%.4f", loss), systemImage: "arrow.down.right")
                            .foregroundColor(.red)
                    }
                }
                .font(.caption)

                // Tags
                if !version.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(version.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        if version.tags.count > 3 {
                            Text("+\(version.tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Notes preview
                if let notes = version.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if !version.isProduction {
                Button {
                    onSetProduction()
                } label: {
                    Label("Set as Production", systemImage: "star.fill")
                }
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(version.id, forType: .string)
            } label: {
                Label("Copy Version ID", systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(version.checkpointPath, forType: .string)
            } label: {
                Label("Copy Checkpoint Path", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Version", systemImage: "trash")
            }
        }
    }
}

// MARK: - Version Detail View

struct VersionDetailView: View {
    let version: ModelVersion
    @State private var editedNotes: String = ""
    @State private var isEditingNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Version \(version.version)")
                                .font(.title2)
                                .fontWeight(.bold)

                            if version.isProduction {
                                Label("Production", systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .cornerRadius(6)
                            }
                        }

                        Text("Created \(version.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Metrics
                if version.accuracy != nil || version.loss != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Performance Metrics")
                            .font(.headline)

                        HStack(spacing: 20) {
                            if let accuracy = version.accuracy {
                                MetricCard(
                                    title: "Accuracy",
                                    value: String(format: "%.2f%%", accuracy * 100),
                                    icon: "chart.line.uptrend.xyaxis",
                                    color: .green
                                )
                            }

                            if let loss = version.loss {
                                MetricCard(
                                    title: "Loss",
                                    value: String(format: "%.4f", loss),
                                    icon: "arrow.down.right",
                                    color: .red
                                )
                            }
                        }
                    }
                }

                // Tags
                if !version.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tags")
                            .font(.headline)

                        VersionFlowLayout(spacing: 8) {
                            ForEach(version.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }

                // Notes
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notes")
                            .font(.headline)

                        Spacer()

                        Button(isEditingNotes ? "Save" : "Edit") {
                            if isEditingNotes {
                                saveNotes()
                            } else {
                                editedNotes = version.notes ?? ""
                            }
                            isEditingNotes.toggle()
                        }
                        .buttonStyle(.borderless)
                    }

                    if isEditingNotes {
                        TextEditor(text: $editedNotes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    } else if let notes = version.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No notes")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)

                    VStack(spacing: 8) {
                        VersionDetailRow(label: "Version ID", value: String(version.id.prefix(12)) + "...")
                        VersionDetailRow(label: "Checkpoint", value: URL(fileURLWithPath: version.checkpointPath).lastPathComponent)

                        if let runId = version.trainingRunId {
                            VersionDetailRow(label: "Training Run", value: String(runId.prefix(12)) + "...")
                        }

                        if let parentId = version.parentVersionId {
                            VersionDetailRow(label: "Parent Version", value: String(parentId.prefix(12)) + "...")
                        }

                        ForEach(Array(version.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            VersionDetailRow(label: key.capitalized, value: value)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
        }
    }

    private func saveNotes() {
        Task {
            try? await ModelVersionManager.shared.updateNotes(versionId: version.id, notes: editedNotes)
        }
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.secondary)
            }
            .font(.caption)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct VersionDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(.body, design: .monospaced))
    }
}

// MARK: - Flow Layout

struct VersionFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Create Version Sheet

struct CreateVersionSheet: View {
    let modelId: String
    let modelName: String
    let onCreated: (ModelVersion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var tags = ""
    @State private var checkpointPath = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Version")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Model") {
                    LabeledContent("Model", value: modelName)
                }

                Section("Checkpoint") {
                    HStack {
                        TextField("Checkpoint path", text: $checkpointPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            browseForCheckpoint()
                        }
                    }
                }

                Section("Details") {
                    TextField("Tags (comma separated)", text: $tags)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Create Version") {
                    createVersion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(checkpointPath.isEmpty || isCreating)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func browseForCheckpoint() {
        let panel = NSOpenPanel()
        panel.title = "Select Checkpoint File"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            checkpointPath = url.path
        }
    }

    private func createVersion() {
        isCreating = true
        errorMessage = nil

        let tagList = tags.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }

        Task {
            do {
                let version = try await ModelVersionManager.shared.createManualVersion(
                    for: modelId,
                    checkpointPath: checkpointPath,
                    notes: notes.isEmpty ? nil : notes,
                    tags: tagList
                )
                await MainActor.run {
                    onCreated(version)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
