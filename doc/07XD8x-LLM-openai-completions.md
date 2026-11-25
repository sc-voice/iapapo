---
agent_instructions: "Follow high-stakes readback/hearback communication protocol with human confirmation before taking any action that changes stored data"
author: "(none)"
collection: world
description: "(none)"
slug: "07XD8x-LLM-openai-completions"
status: "draft"
tags: "(none)"
type: "nameforma.md"
updated: 2026-11-25
zuid: 07XD8xQFmkJB10yIQVLy4e
---

# LLM openai-completions

## Overview

`api = "openai-completions"` selects the OpenAI Chat Completions wire protocol. pi lists it as the most compatible API type, and it works with any OpenAI-compatible server (oMLX, Ollama, LM Studio, vLLM). The `api` value is set on the provider, and a model may override it.

### Endpoints

- Chat: `POST {baseUrl}/chat/completions`
- Discovery: `GET {baseUrl}/models`, parsed by `LLMModelDiscovery` (`VACore/Sources/VACore/LLMModelDiscovery.swift`). It reads `data[].id` and the optional oMLX `max_model_len`.

`baseUrl` is the base that includes `/v1`, for example `http://localhost:8080/v1`. The paths above are appended to it.

### Authentication

`Authorization: Bearer <apiKey>`, sent when the provider has a non-empty key. Keyless local servers need no header. The key lives in the Keychain under the provider's `zuid`.

### Request

- Required: `model` (string) and `messages` (array, at least one item). Each message has `role` and `content`. Roles include `developer`, `system`, `user`, `assistant`, and `tool`.
- Optional: `stream` (boolean, default false), `temperature` (0 to 2, default 1), `max_tokens` (deprecated), `max_completion_tokens`, and `stream_options.include_usage`.
- Use `max_completion_tokens` for the reply cap. It counts reasoning tokens as well as visible output.

### Response

Non-streaming: `id`, `object: "chat.completion"`, `created`, `model`, `choices[].message.content`, `choices[].finish_reason` (`stop`, `length`, `tool_calls`, `content_filter`), and `usage`.

Streaming: server-sent events, each a `data:` line. Chunks have `object: "chat.completion.chunk"` and `choices[].delta`. The stream ends with `data: [DONE]`. With `include_usage`, a final chunk with empty `choices` carries `usage` before `[DONE]`.

### Chat example

Non-streaming request. Replace `MODEL_ID` with a model id from `GET {baseUrl}/models`, and `YOUR_KEY` with the provider key:

```
curl -s http://dinna.local:8000/v1/chat/completions \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "MODEL_ID",
    "messages": [
      {"role": "system", "content": "You are a concise assistant."},
      {"role": "user", "content": "Say hello."}
    ],
    "max_completion_tokens": 64
  }'
```

The reply text is at `choices[0].message.content`. Add `"stream": true` to receive `data:` chunks instead.

### pi model fields

pi's `models.json` entries use these fields for an `openai-completions` provider: `baseUrl`, `api`, `apiKey`, `headers`, `authHeader`, and `models`. Each model takes `id` (required), `name`, `reasoning`, `input`, `contextWindow`, `maxTokens`, `cost`, and `compat`.

### Compatibility flags

`compat` adjusts the wire format for servers that differ from OpenAI. The provider sets defaults and a model may override them. The flags relevant here:

- `supportsDeveloperRole`: set to `false` for servers that reject the `developer` role. pi then sends the system prompt as a `system` message.
- `supportsReasoningEffort`: set to `false` when the server does not accept `reasoning_effort`.
- `supportsUsageInStreaming` (default true) and `supportsStore`.
- `maxTokensField`: `max_completion_tokens` or `max_tokens`.

### Open

- pi's `models.md` gives defaults of `contextWindow` 128000 and `maxTokens` 16384 for `models.json` entries. `LLMModelDefaults` uses 4096 for both, citing pi's `ai/catalog/define.ts` fallbacks. The two sources differ and are not reconciled.
- The app has no chat client yet. Only discovery calls the endpoint. The streaming format above comes from a summary of the OpenAI reference, and the response and streaming details were not checked against verbatim text.

## References

- OpenAI, [Create chat completion](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- OpenAI, [Chat streaming events](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)
- pi coding agent, [models.md](https://unpkg.com/@earendil-works/pi-coding-agent@0.83.0/docs/models.md), version 0.83.0
