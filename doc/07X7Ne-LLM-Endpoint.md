---
agent_instructions: "Follow high-stakes readback/hearback communication protocol with human confirmation before taking any action that changes stored data"
author: "(none)"
collection: world
description: "Specifying and connecting to a local network LLM"
slug: "07X7Ne-LLM-Endpoint"
status: "draft"
tags: "(none)"
type: "nameforma.md"
updated: 2026-11-21
zuid: 07X7NeP8upOBBDAtbkEIPe
---

# LLM Endpoint

## Overview

The IaPapo app needs to send a prompt to a local network LLM and receive the reply, so the ChatState can move from THINKING to SPEAKING. The target is an OpenAI-compatible server on the home LAN, (e.g., first the oMLX server). The app runs on iPad, iPhone, or Mac, so the connection is configured per device, not hard-coded.

A `Sendable` struct, `LLMConfig`, in `VACore`, next to `VAConfig`. It holds everything needed for one connection:

- `zuid`: String, generated once when the config is created and never changed. It is the stable identity, so renames and Keychain keys can rely on it.
- `name`: String, the display name shown in the list and the Active LLM picker. Required in the editor, so the picker never shows a `zuid`. Renaming changes only this field.
- `baseURL`: URL, the only address field. Example: `http://<host>:<port>/v1`. Scheme, host, and port are read from it, so they are not stored separately.
- `api`: String, the protocol. For the local server, `openai-completions`. Matches the `api` field in `models.json`.
- `apiKey`: optional String. Stored in the Keychain, keyed by `zuid`, not in UserDefaults.
- `model`: String, the model ID returned by `/v1/models`, such as `gemma-4-26B-A4B-it-MLX-8bit`.
- `maxTokens`: Int, sent as `max_tokens`. A hard cap on reply length. Required in the settings form and prefilled with the constant 20000 in the app (see Open Issues). The form rejects empty or non-positive values, and values above 1,000,000 (a sanity ceiling for typos such as 1G). The server's own limit, 262144 for current models, is a runtime check to add per model later. No silent fallback in `LLMClient`.
- `timeout`: Double, default `VAConfig.llmTimeout` (60s).

Mapping to pi's `ModelConfig`: `baseURL` → `provider.baseUrl`, `api` → `provider.api`, `apiKey` → `provider.apiKey`, `model` → `model.id`, `maxTokens` → `model.maxTokens`. `timeout` has no pi equivalent and stays in the app.

## Configuration Collection and Selection

- **Collection:** `[String: LLMConfig]`, keyed by `zuid`. The key never changes, so renames and Keychain items stay valid.
- **Active choice:** `activeLLMZUID: String?`, stored beside the collection, not inside each config. The settings picker shows each config's `name` and writes only this value.
- **Which applies:** `activeConfig` returns the config keyed by `activeLLMZUID`. If that key is missing or unset, it falls back to the first `zuid` in sorted order. Because zuids are time-ordered, this is the oldest config, so the choice is deterministic. The pi equivalent is `findInitialModel` (`model-resolver.ts:533`), but we have no scoped models, so the saved default is the only override.

## Storage

- **Files:** `LLMConfig.swift` in `VACore` holds the struct, collection, and `activeConfig` logic. `LLMConfigStore.swift` in the app target holds persistence, beside `AppSettingsStore.swift`.
- **Collection:** one Codable JSON value in UserDefaults.
- **`activeLLMZUID`:** an `@AppStorage` string beside the collection.
- **API keys:** Keychain, keyed by `zuid`, with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The Keychain encrypts at rest with OS-held keys, protected by the device passcode. This attribute keeps keys from syncing to iCloud or moving to another device.
- **Scope:** per device. iCloud sync can come later.

## Settings UI

Lives in the VA app target, next to `VA/VA/SettingsView.swift`.

- **Active LLM:** a `Picker` over the configs, sorted by `zuid`, showing each `name` and bound to `activeLLMZUID`. Disabled with a hint when no configs exist.
- **Config button:** `pencil` with the accessibility label "Add or edit LLM."
- **Config sheet:** a list sheet. Tapping a row or "+" pushes the editor onto the list's navigation stack, with Cancel and Save in its toolbar. Each row has a swipe-to-delete action that asks for confirmation first. Tapping a row opens the form: name, base URL, protocol, model, API key, max tokens (required), and timeout. Each limit row has its label always visible, and timeout shows its unit, "seconds." The API key field has an eye icon (`eye` / `eye.slash`) that toggles between hidden and visible. A "Test connection" button calls `/v1/models`, and it waits for the step 3 client.
- **Deleting the active config:** the confirmation says the app switches to the first remaining config, which the sorted fallback selects.

## Status

- **Step 1, endpoint:** done. The server accepts the key, and `/v1/models` lists the served ID `gemma-4-26B-A4B-it-MLX-8bit`.
- **Step 2, config types:** built and tested in `VACore/Sources/VACore/LLMConfig.swift`, with `zuid`, `name`, `displayName`, `activeLLMZUID`, and `activeConfig`. `maxTokens` must be 1 through 1,000,000. 18 tests in `LLMConfigTests.swift` pass, including the check that sorted `zuid` strings match creation order.
- **Step 5, settings UI and persistence:** built in `VA/VA/LLMConfigStore.swift`, `VA/VA/LLMConfigSheet.swift`, and `VA/VA/SettingsView.swift`. The app builds for the iOS simulator. Not yet run on a device, and "Test connection" waits for step 3.
- **Steps 3, 4, 6, 7:** not started.

## Plan

1. **Confirm the endpoint.** On the server, find the oMLX listen port and whether it needs a key. Run `GET /v1/models` and record the chat model ID.
2. **Add `LLMConfig` and the collection** to `VACore/Sources/VACore/LLMConfig.swift`, with JSDoc on the public interface, including `zuid` generation via the existing `ZUID.swift` and the `activeConfig` fallback. No persistence in this step.
3. **Add an `LLMClient` protocol** with `respond(to prompt: String) async throws -> String`. A factory maps the `api` string to an implementation. Only `openai-completions` exists now, calling `POST /v1/chat/completions` non-streaming. The factory throws on unknown values. The Anthropic client waits until a server needs it. Streaming waits until a need is shown (YAGNI).
4. **Map failures to events.** A timeout emits `llmTimeout`, and any other error emits `llmFailed`. Both drive THINKING → IDLE with `cue(soundError)`. A reply emits `llmResponseReady`, which drives THINKING → SPEAKING.
5. **Add persistence and a settings form.** `LLMConfigStore.swift` saves the collection to UserDefaults and keys to the Keychain. The settings dialog is an accordion with exactly one section open at a time, so its height stays bounded. It has two sections:
   - **LLM:** a picklist for the active config, with a button to add or edit configs (base URL, API key, model, max tokens, timeout), and a "Test connection" button that calls `/v1/models`.
   - **Chat: Listening:** the listen timeout (`listenTimeout`, default 60s), currently in `SettingsView.swift`.
6. **Wire the client into THINKING** for quickPrompt and validPrompt. invalidPrompt and unknownPrompt do not call the LLM.
7. **Test.** Add `VACoreTests` with a mock `LLMClient` covering success, timeout, and error transitions. Then test against the server by hand.

## Open Issues

- Confirm the oMLX port and model ID on the server with the API key. Keep the key out of the doc and the repo.
- Whether `maxTokens` and `timeout` should be per config or per request.
- iOS needs local network permission (Bonjour and `NSLocalNetworkUsageDescription`) and an App Transport Security exception for LAN HTTP.
- Whether a Bonjour lookup for the server is more reliable than a fixed IP.
- Clef is a separate decision client. It is out of scope for this plan.
- The sync-duplex design wants short replies. Whether to ask the model for brevity in the system prompt is open.
- The `maxTokens` prefill is a constant (20000) in the app. It is not read from `models.json`. A per-model default is open.
- Deleting the active config silently switches the active one to the oldest remaining. The delete confirmation should name the replacement.
- Device-only Keychain keys do not survive a restore or new device. The editor should tell the user to re-enter the key.
- Naming: the stored selection is `activeLLMZUID`, which matches the "Active LLM" picker label. The resolved property is `activeConfig`, so "active" in the stored name means the user's choice, and the resolved config is what runs.

## References

- [07WVS9-IaPapo-Voice-Assistant](07WVS9-IaPapo-Voice-Assistant.md): state machine, defaults, and the Clef and oMLX glossary entries.
- `VACore/Sources/VACore/VAConfig.swift`: timeout defaults.
- `VACore/Sources/VACore/VAEvent.swift`: `llmResponseReady` and `llmFailed` events.
