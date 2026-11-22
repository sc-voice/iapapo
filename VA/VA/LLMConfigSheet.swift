import SwiftUI
import VACore

/// Sheet for adding, editing, and deleting LLM configs. Each change is saved as it is made.
struct LLMConfigSheet: View {
  @Environment(\.dismiss) private var dismiss
  /// The configs being edited, keyed by `zuid`. Written back through `LLMConfigStore`.
  @State private var configs: [String: LLMConfig] = LLMConfigStore.load()
  /// The config whose editor is showing, or nil on the list.
  @State private var editing: LLMConfig?
  /// True when the editor is adding a new config rather than changing one.
  @State private var isNew = false
  /// The config awaiting delete confirmation, or nil.
  @State private var pendingDelete: LLMConfig?

  /// The configs sorted by `zuid`, the same order as the Settings picker.
  private var sorted: [LLMConfig] {
    configs.values.sorted { $0.zuid < $1.zuid }
  }

  var body: some View {
    NavigationStack {
      List {
        if sorted.isEmpty {
          Text("No LLM configs yet. Tap + to add one.")
            .foregroundStyle(.secondary)
        }
        ForEach(sorted, id: \.zuid) { config in
          Button {
            isNew = false
            editing = config
          } label: {
            VStack(alignment: .leading) {
              Text(config.name)
              Text(config.model)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .tint(.primary)
          .swipeActions {
            Button(role: .destructive) {
              pendingDelete = config
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle("LLMs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            isNew = true
            editing = newConfig()
          } label: {
            Label("Add LLM", systemImage: "plus")
          }
        }
      }
      .navigationDestination(item: $editing) { config in
        LLMConfigEditor(config: config, isNew: isNew) { saved, apiKey in
          configs[saved.zuid] = saved
          LLMConfigStore.save(configs)
          LLMConfigStore.setAPIKey(apiKey, for: saved.zuid)
        }
      }
    }
    .confirmationDialog(
      "Delete \(pendingDelete?.name ?? "this LLM")?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let config = pendingDelete { remove(config) }
        pendingDelete = nil
      }
    } message: {
      Text("If this is the active LLM, the app switches to the first remaining config.")
    }
  }

  /// A config with the defaults from the design doc, for the editor to start from.
  private func newConfig() -> LLMConfig {
    LLMConfig(
      name: "",
      baseURL: URL(string: "http://localhost:8000/v1")!,
      api: "openai-completions",
      model: "",
      maxTokens: 20000
    )
  }

  /// Removes one config and its Keychain key, after the user confirms.
  private func remove(_ config: LLMConfig) {
    configs[config.zuid] = nil
    LLMConfigStore.removeAPIKey(for: config.zuid)
    LLMConfigStore.save(configs)
  }
}

/// Form for one config. Save is enabled only when the config is valid and has a model.
struct LLMConfigEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: LLMConfig
  @State private var apiKey: String
  /// Whether the API key is shown in clear text.
  @State private var showKey = false
  private let isNew: Bool
  /// Called with the edited config and its API key when Save is tapped.
  private let onSave: (LLMConfig, String?) -> Void

  init(config: LLMConfig, isNew: Bool, onSave: @escaping (LLMConfig, String?) -> Void) {
    _draft = State(initialValue: config)
    _apiKey = State(initialValue: config.apiKey ?? LLMConfigStore.readAPIKey(for: config.zuid) ?? "")
    self.isNew = isNew
    self.onSave = onSave
  }

  /// Save is allowed when the config passes `isValid`, has a name, and names a model.
  private var canSave: Bool {
    draft.isValid
      && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
      && !draft.model.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    Form {
        Section {
          TextField("Name", text: $draft.name)
        } footer: {
          Text("Required. This is the name shown in the Active LLM picker.")
        }
        Section {
          TextField("Base URL", value: $draft.baseURL, format: .url)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Protocol", text: $draft.api)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Model ID", text: $draft.model)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Server")
        } footer: {
          Text("Use the base URL of an OpenAI-compatible server, such as http://host:port/v1.")
        }
        Section {
          HStack {
            Group {
              if showKey {
                TextField("API key", text: $apiKey)
              } else {
                SecureField("API key", text: $apiKey)
              }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
              showKey.toggle()
            } label: {
              Image(systemName: showKey ? "eye.slash" : "eye")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showKey ? "Hide API key" : "Show API key")
          }
        } header: {
          Text("Access")
        } footer: {
          Text("The key is stored in the Keychain on this device only.")
        }
        Section {
          LabeledContent("Max tokens") {
            TextField("20000", value: $draft.maxTokens, format: .number)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Timeout") {
            HStack {
              TextField("60", value: $draft.timeout, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
              Text("seconds")
                .foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Limits")
        } footer: {
          Text("Max tokens is the longest reply the model may send, from 1 to \(LLMConfig.maxTokensLimit.formatted()). Timeout is how long to wait for a reply before giving up.")
        }
      }
      .navigationTitle(isNew ? "New LLM" : "Edit LLM")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(draft, apiKey.isEmpty ? nil : apiKey)
            dismiss()
          }
          .disabled(!canSave)
        }
      }
  }
}
