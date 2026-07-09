import AppKit
import SQLiteData
import SwiftUI
import VinylFeverCore

/// The recipe workbench (M7 S1). A new top-level section, peer to Live Shows and
/// Collections: author a Collection Policy, hang a deterministic recipe off it, point
/// it at a Finder folder, preview the proposed diffs on a real sample, and apply
/// through the existing `copy → Working/ → writeTags` rail. Single-recipe, model-off;
/// the `useModel`/`prompt` fields are inert until S2. Clones `CollectionsView`.
struct PoliciesView: View {
  @Bindable var model: AppModel
  @FetchAll(CollectionPolicy.order(by: \.name))
  private var policies: [CollectionPolicy]
  @FetchAll(CollectionRecipe.order(by: \.name))
  private var recipes: [CollectionRecipe]
  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]

  @State private var selectedPolicyID: CollectionPolicy.ID?
  @State private var draftRecipe: CollectionRecipe?

  private var selectedPolicy: CollectionPolicy? {
    policies.first { $0.id == selectedPolicyID }
  }

  private var policyRecipes: [CollectionRecipe] {
    guard let selectedPolicyID else { return [] }
    return recipes.filter { $0.collectionPolicyID == selectedPolicyID }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PoliciesHeader(newPolicy: { model.createPolicy(name: "New Policy") })
        PolicyRegistrySection(
          policies: policies,
          selectedPolicyID: $selectedPolicyID,
          rename: { model.savePolicy($0) },
          delete: { model.deletePolicy($0) }
        )
        if let selectedPolicy {
          RecipeListSection(
            recipes: policyRecipes,
            selectedRecipeID: draftRecipe?.id,
            newRecipe: {
              if let created = model.createRecipe(for: selectedPolicy.id) {
                draftRecipe = created
              }
            },
            select: { draftRecipe = $0 }
          )
        }
        if let recipeBinding = Binding($draftRecipe) {
          RecipeEditorSection(
            recipe: recipeBinding,
            sampleFolder: model.recipeSampleFolder,
            sampleState: model.recipeSampleState,
            sampleItems: model.recipeSampleItems,
            applyState: model.recipeApplyState,
            save: { model.saveRecipe(recipeBinding.wrappedValue) },
            delete: {
              model.deleteRecipe(recipeBinding.wrappedValue)
              draftRecipe = nil
            },
            pickFolder: pickSampleFolder,
            apply: { Task { await model.applyRecipePlan() } }
          )
        }
      }
      .frame(maxWidth: 1040, alignment: .leading)
      .padding(24)
    }
    .navigationTitle("Policies")
    .onChange(of: selectedPolicyID) {
      draftRecipe = nil
      model.clearRecipeSample()
    }
    .onChange(of: draftRecipe) {
      runPreview()
    }
    .task(id: AppSetting.current(from: persistedSettings)) {
      await model.refreshToolStatuses(settings: AppSetting.current(from: persistedSettings))
    }
  }

  /// Re-run the live sample whenever the recipe is edited. Reuses the cached folder
  /// read (engine only, no re-reading of metadata); a no-op until a folder is chosen,
  /// so editing before picking a folder is silent.
  private func runPreview() {
    guard let recipe = draftRecipe else { return }
    Task { await model.recomputeRecipeSample(recipe: recipe) }
  }

  private func pickSampleFolder() {
    guard let recipe = draftRecipe, let url = openFolder(prompt: "Preview") else { return }
    Task { await model.buildRecipeSample(recipe: recipe, folder: url) }
  }

  private func openFolder(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = false
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
  }
}

// MARK: - Header

private struct PoliciesHeader: View {
  let newPolicy: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Collection Policies")
          .font(.title2)
          .fontWeight(.semibold)
        Text("Author a recipe, preview its diffs on a real folder, then apply stamped copies to Working.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: newPolicy) {
        Label("New Policy", systemImage: "plus")
      }
    }
  }
}

// MARK: - Policy registry

private struct PolicyRegistrySection: View {
  let policies: [CollectionPolicy]
  @Binding var selectedPolicyID: CollectionPolicy.ID?
  let rename: (CollectionPolicy) -> Void
  let delete: (CollectionPolicy) -> Void

  var body: some View {
    PolicySection(title: "Policies", systemImage: "slider.horizontal.3", count: policies.count) {
      if policies.isEmpty {
        EmptyPolicyRow(title: "No policies yet — create one to hang a recipe off of")
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(policies) { policy in
            PolicyRow(
              policy: policy,
              isSelected: selectedPolicyID == policy.id,
              select: { selectedPolicyID = policy.id },
              rename: rename,
              delete: {
                if selectedPolicyID == policy.id {
                  selectedPolicyID = nil
                }
                delete(policy)
              }
            )
          }
        }
      }
    }
  }
}

private struct PolicyRow: View {
  let policy: CollectionPolicy
  let isSelected: Bool
  let select: () -> Void
  let rename: (CollectionPolicy) -> Void
  let delete: () -> Void
  @State private var name: String

  init(
    policy: CollectionPolicy,
    isSelected: Bool,
    select: @escaping () -> Void,
    rename: @escaping (CollectionPolicy) -> Void,
    delete: @escaping () -> Void
  ) {
    self.policy = policy
    self.isSelected = isSelected
    self.select = select
    self.rename = rename
    self.delete = delete
    _name = State(initialValue: policy.name)
  }

  var body: some View {
    HStack(spacing: 12) {
      Button(action: select) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      TextField("Policy name", text: $name)
        .textFieldStyle(.plain)
        .onSubmit { commitRename() }
        .font(.headline)
      Spacer()
      Button(role: .destructive, action: delete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
    .onTapGesture(perform: select)
  }

  private func commitRename() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != policy.name else { return }
    var updated = policy
    updated.name = trimmed
    rename(updated)
  }
}

// MARK: - Recipe list

private struct RecipeListSection: View {
  let recipes: [CollectionRecipe]
  let selectedRecipeID: CollectionRecipe.ID?
  let newRecipe: () -> Void
  let select: (CollectionRecipe) -> Void

  var body: some View {
    PolicySection(title: "Recipes", systemImage: "wand.and.rays", count: recipes.count) {
      VStack(alignment: .leading, spacing: 12) {
        if recipes.isEmpty {
          EmptyPolicyRow(title: "No recipes in this policy yet")
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(recipes) { recipe in
              Button {
                select(recipe)
              } label: {
                RecipeRow(recipe: recipe, isSelected: selectedRecipeID == recipe.id)
              }
              .buttonStyle(.plain)
            }
          }
        }
        Button(action: newRecipe) {
          Label("New Recipe", systemImage: "plus")
        }
      }
    }
  }
}

private struct RecipeRow: View {
  let recipe: CollectionRecipe
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: recipe.enabled ? "checkmark.seal" : "seal")
        .foregroundStyle(recipe.enabled ? Color.green : .secondary)
      VStack(alignment: .leading, spacing: 4) {
        Text(recipe.name)
          .font(.headline)
        Text("\(recipe.op.displayName) → \(recipe.targetField.displayName)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isSelected {
        Image(systemName: "chevron.right")
          .foregroundStyle(.tint)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

// MARK: - Recipe editor + live sample

private struct RecipeEditorSection: View {
  @Binding var recipe: CollectionRecipe
  let sampleFolder: URL?
  let sampleState: RecipeSampleState
  let sampleItems: [RecipeSampleItem]
  let applyState: ApplyRunState
  let save: () -> Void
  let delete: () -> Void
  let pickFolder: () -> Void
  let apply: () -> Void

  private var applicableCount: Int {
    sampleItems.count { !$0.hasIssues }
  }

  var body: some View {
    PolicySection(title: "Recipe", systemImage: "wand.and.stars", count: sampleItems.count) {
      VStack(alignment: .leading, spacing: 16) {
        RecipeEditorForm(recipe: $recipe)
        HStack {
          Button(action: save) {
            Label("Save Recipe", systemImage: "checkmark")
          }
          Button(role: .destructive, action: delete) {
            Label("Delete", systemImage: "trash")
          }
          Spacer()
          Button(action: pickFolder) {
            Label(sampleFolder == nil ? "Choose Sample Folder…" : "Change Folder…", systemImage: "folder")
          }
        }
        if let sampleFolder {
          Text(sampleFolder.path(percentEncoded: false))
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        RecipeSampleStatus(state: sampleState)
        if !sampleItems.isEmpty {
          HStack {
            Label("\(applicableCount) ready to apply", systemImage: "checkmark.circle")
              .foregroundStyle(.green)
            Spacer()
            Button(action: apply) {
              Label("Apply to Working", systemImage: "square.and.arrow.down")
            }
            .disabled(applicableCount == 0 || applyState.isRunning)
          }
          RecipeApplyStatus(state: applyState)
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(sampleItems) { item in
              RecipeDiffRow(item: item)
            }
          }
        }
      }
    }
  }
}

private struct RecipeEditorForm: View {
  @Binding var recipe: CollectionRecipe

  private var stringFields: [ProposedTags.Field] {
    ProposedTags.Field.allCases.filter(\.isStringValued)
  }

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
      GridRow {
        Text("Name").foregroundStyle(.secondary)
        TextField("Recipe name", text: $recipe.name)
          .textFieldStyle(.roundedBorder)
      }
      GridRow {
        Text("Operation").foregroundStyle(.secondary)
        Picker("Operation", selection: $recipe.op) {
          ForEach(CollectionRecipe.Op.allCases, id: \.self) { op in
            Text(op.displayName).tag(op)
          }
        }
        .labelsHidden()
      }
      GridRow {
        Text("Target Field").foregroundStyle(.secondary)
        Picker("Target Field", selection: $recipe.targetField) {
          ForEach(stringFields, id: \.self) { field in
            Text(field.displayName).tag(field)
          }
        }
        .labelsHidden()
      }
      GridRow {
        Text("Pattern").foregroundStyle(.secondary)
        TextField("Regex pattern", text: $recipe.pattern)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
      }
      if recipe.op != .strip {
        GridRow {
          Text("Capture").foregroundStyle(.secondary)
          TextField("Named capture", text: $recipe.captureName)
            .textFieldStyle(.roundedBorder)
        }
      }
      if recipe.op == .appendIfAbsent {
        GridRow {
          Text("Affix").foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            TextField("Affix template", text: $recipe.affixTemplate)
              .textFieldStyle(.roundedBorder)
            Text("`{value}` is replaced with the captured text.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      GridRow {
        Text("Enabled").foregroundStyle(.secondary)
        Toggle("Enabled", isOn: $recipe.enabled)
          .labelsHidden()
      }
      GridRow {
        Text("Model").foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 4) {
          Toggle("Use on-device model", isOn: $recipe.useModel)
            .disabled(true)
          TextField("Classification prompt", text: $recipe.prompt, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .disabled(true)
          Label("The model classify stage arrives in S2.", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct RecipeDiffRow: View {
  let item: RecipeSampleItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(item.filename)
          .font(.headline)
        Spacer()
        if item.hasIssues {
          Label("Needs review", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
        GridRow {
          Text(item.fieldLabel)
            .foregroundStyle(.secondary)
          Text(item.current ?? "none")
          Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
          Text(item.proposed ?? "removed")
            .fontWeight(.medium)
        }
      }
      .font(.caption)
      if !item.proposal.reason.isEmpty {
        Text(item.proposal.reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      ForEach(item.proposal.issues, id: \.displayMessage) { issue in
        Label(issue.displayMessage, systemImage: "exclamationmark.triangle")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
    }
    .padding(12)
    .background((item.hasIssues ? Color.orange : Color.secondary).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

private struct RecipeSampleStatus: View {
  let state: RecipeSampleState

  var body: some View {
    switch state {
    case .idle:
      EmptyPolicyRow(title: "Choose a sample folder to preview this recipe's diffs")
    case .running:
      Label("Reading folder", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .completed(scanned, proposed):
      Label("\(proposed) of \(scanned) files touched", systemImage: "checkmark.circle")
        .foregroundStyle(proposed == 0 ? Color.secondary : Color.green)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }
}

private struct RecipeApplyStatus: View {
  let state: ApplyRunState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running:
      Label("Applying tags to Working copies", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .completed(result):
      Label(result.exitSummary, systemImage: result.didSucceed ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(result.didSucceed ? .green : .orange)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }
}

// MARK: - Shared chrome

private struct PolicySection<Content: View>: View {
  let title: String
  let systemImage: String
  let count: Int
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(title, systemImage: systemImage)
          .font(.headline)
        Spacer()
        Text("\(count)")
          .foregroundStyle(.secondary)
      }
      content
    }
    .padding(.vertical, 4)
  }
}

private struct EmptyPolicyRow: View {
  let title: String

  var body: some View {
    Text(title)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }
}

extension RecipeIssue {
  var displayMessage: String {
    switch self {
    case .valueNotInFilename:
      "The proposed value doesn't appear in the filename."
    case .modelOutputUnparseable:
      "The model returned something unparseable."
    }
  }
}
