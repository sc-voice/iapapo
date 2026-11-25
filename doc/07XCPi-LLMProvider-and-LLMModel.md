---
agent_instructions: "Follow high-stakes readback/hearback communication protocol with human confirmation before taking any action that changes stored data"
author: "(none)"
collection: world
description: "(none)"
slug: "07XCPi-LLMProvider-and-LLMModel"
status: "draft"
tags: "(none)"
type: "nameforma.md"
updated: 2026-11-25
zuid: 07XCPi48dZwClhKq4DcIvX
---

# LLMProvider and LLMModel

## Overview

`LLMConfig` is deprecated. Its replacement is `LLMProvider`, which matches pi's vocabulary: pi calls a configured endpoint a "provider," not a "server."

### LLMProvider

Fields use pi's names where pi has them:

- `zuid`: IaPapo identity (not in pi). Keys the Keychain item.
- `name`: pi `name`.
- `baseUrl`: pi `baseUrl`. Empty string for providers with no endpoint, such as the Apple provider.
- `api`: pi `api`, such as `openai-completions` or `apple-foundation-models`.
- `apiKey`: pi `apiKey`. Excluded from Codable. Stored in the Keychain under `zuid`.
- `models`: `[LLMModel]`, matching pi's `providers.<id>.models`.

### LLMModel

Existing type, unchanged in shape. `provider` is set from the parent `LLMProvider` when saving, so the two cannot disagree.

### Discovery

`/v1/models` supplies model ids. Pi's `Model` requires `contextWindow`, `maxTokens`, `cost`, `input`, and `reasoning`, so discovered entries get defaults until the user edits them.

Defaults are hardcoded in the app, taken from pi's catalog fallbacks (`ai/catalog/define.ts`): `maxTokens` 4096, `input` text, `reasoning` false, zero cost, and `contextWindow` 4096 when the server reports none. Pi has no per-API table, so the same values apply to every `api`. The user can override any field.

The server may report a context window (oMLX `max_model_len`). When it does, that value is used as `contextWindow`. All other fields always come from the defaults. Implemented in `LLMModelDefaults` and `LLMProvider.addDiscoveredModel` in `VACore/Sources/VACore/LLMProvider.swift`.

### Apple Foundation Models

`api = "apple-foundation-models"` selects Apple's on-device model, served by the Foundation Models framework. This is the default provider: `LLMProvider.appleFoundationModels`, with `name = "apple-foundation-model"` and a fixed `zuid`. It is offered on first run, when no providers are saved. Apple's framework has no URL and no key, so this provider:

- has `baseUrl = ""` and no `apiKey`;
- has no discovery. Its models are fixed, with one model `id = "system"`, which maps to `SystemLanguageModel`;
- reads `contextWindow` from `SystemLanguageModel.default.contextSize`, the maximum tokens the model supports. It uses `LLMModelDefaults` for `maxTokens`, since Apple does not report that value.

Minimum OS: **iOS 27.0** (and macOS 27.0, visionOS 27.0, watchOS 27.0). The SDK declares `LanguageModel` and `LanguageModelExecutor` with `@available(iOS 27.0, …)`. The deployment target is currently iOS 26.x, so it must rise for this provider. Verified against Xcode 27.2 (iOS 27.2 SDK).

The runtime client is planned as `AppleFoundationModelsClient` in VACore, behind `#if canImport(FoundationModels)`. It is not implemented yet.

### Settings

`defaultProvider` is canonical. It selects the provider, and `defaultModel` selects the model, matching pi's names so the settings file stays compatible with pi's. `activeLLM` is retired, and `inferenceServer` is not used. Per-role keys, such as `decisionProvider` and `decisionModel`, are deferred until a role needs them.

### Open


### Fallback order

For a role, the provider is resolved in this order:

1. The role-specific provider, when set.
2. `defaultProvider`.

The model follows the same order: the role's model, then `defaultModel`. A stale id at either step falls through to the next.

## References

(none)
