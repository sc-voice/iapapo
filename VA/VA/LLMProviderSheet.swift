import SwiftUI
import VACore

/// Sheet for adding, editing, and deleting LLM providers. Each change is saved as it is made.
struct LLMProviderSheet: View {
  @Environment(\.dismiss) private var dismiss
  /// The providers shown in the list, reloaded from `LLMProviderStore` after each change.
  @State private var providers: [LLMProvider] = LLMProviderStore.load()
  /// The provider whose editor is showing, or nil on the list.
  @State private var editing: LLMProvider?
  /// True when the editor is adding a new provider rather than changing one.
  @State private var isNew = false
  /// The provider awaiting delete confirmation, or nil.
  @State private var pendingDelete: LLMProvider?

  init() {
    VALogger.log.info("providers sheet init")
  }

  var body: some View {
    NavigationStack {
      List {
        if providers.isEmpty {
          Text("No providers yet. Tap + to add one.")
            .foregroundStyle(.secondary)
        }
        ForEach(providers) { provider in
          Button {
            isNew = false
            editing = provider
          } label: {
            VStack(alignment: .leading) {
              Text(provider.displayName)
              Text("\(provider.baseUrl) · \(provider.models.count) models")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .tint(.primary)
          .swipeActions {
            Button(role: .destructive) {
              pendingDelete = provider
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle("LLM Providers")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            isNew = true
            let zuid = ZUID.create()
            editing = LLMProvider(
              zuid: zuid,
              name: "\(zuid.text.prefix(6)): Inference LLM",
              baseUrl: "http://localhost:8000/v1",
              api: "openai-completions")
          } label: {
            Label("Add provider", systemImage: "plus")
          }
        }
      }
      .navigationDestination(item: $editing) { provider in
        LLMProviderEditor(provider: provider, isNew: isNew) {
          providers = LLMProviderStore.load()
        }
      }
    }
    .onAppear { VALogger.log.info("providers sheet appeared") }
    .confirmationDialog(
      "Delete \(pendingDelete?.displayName ?? "this provider")?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let provider = pendingDelete { remove(provider) }
        pendingDelete = nil
      }
    } message: {
      Text("Its API key is removed from the Keychain. If it is the default provider, the first remaining provider takes its place.")
    }
  }

  /// Removes one provider, its Keychain key, and its defaults, after the user confirms.
  private func remove(_ provider: LLMProvider) {
    providers.removeAll { $0.id == provider.id }
    LLMProviderStore.removeAPIKey(for: provider.id)
    LLMProviderStore.save(providers)
    LLMProviderStore.forgetDefaults(ifProvider: provider.id)
  }
}

/// Form for one provider. Save stores the provider and its key, then fetches the models it serves.
struct LLMProviderEditor: View {
  /// Where a model fetch stands.
  enum FetchState: Equatable {
    case idle
    case fetching
    case failed(String)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var draft: LLMProvider
  @State private var apiKey: String
  /// Whether the API key is shown in clear text.
  @State private var showKey = false
  @State private var fetchState: FetchState = .idle
  /// True while a test chat is in flight.
  @State private var testing = false
  /// Reply or error text from the last test chat.
  @State private var testResult: String?
  private let isNew: Bool
  /// Called after each successful save, so the list can reload.
  private let onSaved: () -> Void

  init(provider: LLMProvider, isNew: Bool, onSaved: @escaping () -> Void) {
    _draft = State(initialValue: provider)
    _apiKey = State(initialValue: provider.apiKey ?? LLMProviderStore.readAPIKey(for: provider.id) ?? "")
    self.isNew = isNew
    self.onSaved = onSaved
  }

  /// True when the base URL parses as an http or https URL with a host.
  private var baseURLIsValid: Bool {
    let text = draft.baseUrl.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
    return ["http", "https"].contains(scheme) && url.host != nil
  }

  var body: some View {
    Form {
      Section {
        TextField("Name", text: $draft.name)
      } footer: {
        Text("Optional. This is the name shown in the provider and model pickers.")
      }
      Section {
        TextField("Base URL", text: $draft.baseUrl)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        LabeledContent("API", value: draft.api)
      } header: {
        Text("Server")
      } footer: {
        Text("The base URL of an OpenAI-compatible server, such as http://host:port/v1.")
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
        Button {
          fetchModels(thenDismiss: false)
        } label: {
          Label(fetchState == .fetching ? "Fetching…" : "Fetch models", systemImage: "arrow.clockwise")
        }
        .disabled(!baseURLIsValid || fetchState == .fetching)
        if case .failed(let message) = fetchState {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
        }
        ForEach(draft.models, id: \.id) { model in
          LabeledContent(model.displayName) {
            Text("\(model.contextWindow.formatted()) ctx")
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Models (\(draft.models.count))")
      } footer: {
        Text("Fetching adds the models the server lists. Models already here keep their settings.")
      }
      Section {
        Button {
          testProvider()
        } label: {
          Label(testing ? "Testing…" : "Test", systemImage: "paperplane")
        }
        .disabled(testing)
        if let testResult {
          Text(testResult)
            .font(.footnote)
            .textSelection(.enabled)
        }
      } header: {
        Text("Test")
      } footer: {
        Text("Sends \"\(LLMProvider.testUserQuestion)\" with the system instruction \"\(LLMProvider.testSystemInstruction)\" using the first model.")
      }
    }
    .navigationTitle(isNew ? "New Provider" : "Edit Provider")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          save()
        }
        .disabled(!baseURLIsValid || fetchState == .fetching)
      }
    }
  }

  /// Stores the key and the provider, then fetches models. The editor closes only when the fetch succeeds.
  private func save() {
    draft.baseUrl = draft.baseUrl.trimmingCharacters(in: .whitespaces)
    LLMProviderStore.setAPIKey(apiKey.isEmpty ? nil : apiKey, for: draft.id)
    persist()
    fetchModels(thenDismiss: true)
  }

  /// Writes the draft into the saved list, then sets defaults if this provider is the first one.
  private func persist() {
    var all = LLMProviderStore.load()
    if let index = all.firstIndex(where: { $0.id == draft.id }) {
      all[index] = draft
    } else {
      all.append(draft)
    }
    LLMProviderStore.save(all)
    LLMProviderStore.adoptDefaults(for: draft)
    onSaved()
  }

  /// Fetches the server's models and adds the new ones to the draft, then saves.
  /// - Parameter thenDismiss: close the editor after a successful fetch.
  private func fetchModels(thenDismiss: Bool) {
    fetchState = .fetching
    let key = apiKey.isEmpty ? nil : apiKey
    let baseUrl = draft.baseUrl
    Task {
      do {
        let discovered = try await LLMModelDiscovery.fetchModels(baseUrl: baseUrl, apiKey: key)
        for model in discovered {
          draft.addDiscoveredModel(model)
        }
        persist()
        fetchState = .idle
        if thenDismiss { dismiss() }
      } catch {
        fetchState = .failed(Self.message(for: error))
      }
    }
  }

  /// Sends "hello" with the instruction "include time of day" to this provider and shows the reply or error.
  private func testProvider() {
    var provider = draft
    provider.apiKey = apiKey.isEmpty ? nil : apiKey
    testing = true
    testResult = nil
    Task {
      do {
        let reply = try await provider.testChat()
        testResult = reply
        voiceSpeaker.say(reply)
      } catch {
        testResult = "Error: \(error)"
        voiceSpeaker.say("Error: \(error)")
      }
      testing = false
    }
  }

  /// A short, user-facing reason for a failed fetch.
  private static func message(for error: Error) -> String {
    switch error as? LLMModelDiscoveryError {
    case .invalidBaseURL: "The base URL is not valid."
    case .badStatus(let code): "The server returned HTTP \(code)."
    case .malformedResponse: "The server's reply was not a model list."
    case nil: "Could not reach the server: \(error.localizedDescription)"
    }
  }
}
