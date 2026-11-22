---
type: nameforma.md
zuid: 07WVS9uFuAQ9uLB4vuKkF2
collection: world
title: "07WVS9-IaPapo-Voice-Assistant"
description: Describes voice/chat design for MacOS 27+ and iOS 27+
agent_instructions: Maintain synchronous awareness without a persistent urge to solve or fix anything until a consensus call to action emerges.
---

## Overview 

Traditional voice assistants/agent chat designs focus on half-duplex and full-duplex, which are two extremes ranging from rigid turn-taking to "anything goes" with multiple voices talking.
Neither extreme works well for a synchronous human/agent dialog that can build shared understanding quickly and efficiently. 
With rigid turn-taking the human often has to deal with an agentic tsunami of words from an LLM trained to respond in massive detail.
With full-duplex comes the challenge of agents talking to themselves and humans having to interrupt constantly.

The IaPapo voice agent is designed to support sync-duplex as a restrained version of full-duplex characterized by short, precise and meaningful exchanges of information.
Sync-duplex avoids agentic bloviation in favor of light-weight rapid exchanges of atomic information.
Agents are trained to converge quickly to a "correct answer", even though different people need different correct answers. In other words, "correctness" is actually ambiguous. 
Response bloviation is a hack to avoid having to deal with conversational ambiguity.
Sync-duplex minimizes bloviation by using a decision model to that guides the conversation towards specific patterns that are terse, crisp and atomic in their approach to building shared understanding.
A mindless conversation pattern would be to send an LLM a request to "explain quicksort" and get back a massive word tsunami. 
A synchronous conversation pattern would be to send an LLM a request to "Explain quicksort in three sentences", which automatically leads to a terse (and ambiguous) response.
There are actually multiple synchronous conversation patterns we use in daily life: "when will the store be restocked?", "a tomato is a fruit", "how do i convert from inches to centimeters?".

The existence of conversational patterns implies a need to classify them for processing.
And that is where a decision model comes in handy. 
A decision model can direct synchronous conversation by classifying prompts so that the general inference LLM can respond appropriately for a given conversation pattern.
Sync-duplex is therefore built upon a foundation of atomic and nimble conversation patterns that foster synchronous human/agent dialogs.

### Use Cases

The primary use case is for an iPad mobile voice assistant on a local network having access to a local inference LLM as the ideal configuration. Secondary use cases include:
* iPhone on home network
* iPhone on internet
* cloud main inference LLM
* iOS for Mac on home network

### ChatState: A Conversation Model

To explore patterns useful for synchronous conversation, it is helpful to have a state machine (ChatState) that describes how any given conversation might flow.

The following state diagram illustrates how we might use synchronous conversation patterns to guide conversation.
The first pattern is clearly just the standard wakeWord which brings a voice assistant from IDLE to LISTENING.
Once the agent is LISTENING, then a quickPrompt pattern (e.g. "what time is it?") can be recognized and processed to provide an immediate response.
Or the user might provide a longPrompt (e.g., "tell me about The Beatles") that would lead to a few paragraphs that the user might need to interrupt if the response was too lengthy.
With longPrompt, we also need an idleWord that would bring the agent to IDLE once again.


```mermaid
stateDiagram-v2
    [*] --> INACTIVE
    INACTIVE -> IDLE : onEnableAgent(on) → mic(on), cue(soundOn)
    IDLE --> LISTENING : onHear(wakeWord) → cue(soundListen)
    IDLE -> INACTIVE : onDisableAgent(off) → mic(off), cue(soundOff)
    LISTENING --> THINKING : quickPrompt 
    LISTENING --> THINKING : validPrompt and endPromptTimeout
    LISTENING --> SPEAKING : invalidPrompt and endPromptTimeout → speak(clarifyRequest)
    LISTENING --> LISTENING : unknownPrompt → keep listening
    THINKING --> SPEAKING : LLM Response Ready
    THINKING --> IDLE : llmTimeout or Error → cue(soundError), cancelThink()
    THINKING --> IDLE : onHear(idleWord) → cue(soundIdle), cancelThink()
    SPEAKING --> IDLE : onHear(idleWord) → cue(soundIdle), cancelSpeech()
    SPEAKING --> LISTENING : Audio Finished → cue(soundListen)
    SPEAKING --> LISTENING : onHear(wakeWord) → cancelSpeech(), cue(soundListen)
    LISTENING --> IDLE : listenTimeout → cue(soundIdle)
    LISTENING --> IDLE : onHear(idleWord) → cue(soundIdle)
```

**Example defaults:**
    * agentName is "IaPapo" (ee-a-PAH-poh)
    * llmTimeout is 60s
    * listenTimeout is 60s
    * endPromptTimeout is 3s
    * wakePause is 500ms
    * wakeWord is agentName followed by wakePause
    * idleWord is agentName

**Prompt classes** (a classifier labels the user's utterance):
    * quickPrompt: an immediate, well-understood request by convention. Goes to THINKING without waiting for endPromptTimeout.
    * validPrompt: a question, a demand, or a request for action.
    * invalidPrompt: thought babble. Answered with speak(clarifyRequest).
    * unknownPrompt: cannot yet be classified. The agent keeps listening, and the classifier re-evaluates the cumulative utterance as more text arrives.

### Sync Chat vs. Conventional Coding Agent Chat

| Dimension | fix-it-chat | sync-chat |
|---|---|---|
| Goal | Resolve the human's request | Establish shared comprehension |
| Success test | Answer is correct | Comprehension is mutually verifiable |
| Turns | Ends after one answer | Includes validation turns |
| Metric | Minimal time to fix | Minimal words to validate mutual comprehension |

#### Example: Teacher and Student

A student has no way to verify a teacher's initial explanation except her own internal state. Comprehension evolves through questions in both directions. The teacher probes the student's understanding to find gaps, and the student probes the teacher's meaning to pin down what is intended. Both converge on a synchronized understanding of the topic.

Verification is therefore mutual probing rather than checking an answer. Each exchange narrows the gap, and the metric counts how few words it takes to reach shared understanding. A teacher who asks one precise question and gets one precise answer has validated more with fewer words than a teacher who lectures at length without confirming anything landed.

### Hardware/Software 

For simplicity, we assume a hardware/software environment having Apple MacOS/iOS 27+ with 2026 hardware, with a focus on iOS software that can also run on macOS without modification.
This Apple environment provides a rich set of tools for implementing on-device voice agents that can link to both local and cloud inference models as the main LLM.
In particular, Apple provides tools for TTS, STT and even has a tiny LLM on iOS mobile devices.

### Prototype User Interface

A SwiftUI `TabView` with two tabs:
- **Home:** the agent name "IaPapo" as a large title.
- **Developer:** live view of the ChatState, InputState (microphone ON/OFF), and the cue now playing (fades out when the cue ends), plus the prompt as it is being spoken and processed.

### STT Vocabulary

Domain terms must survive speech-to-text: "Chaat" is heard, "CHAT" is wanted. Two layers:
- **Recognition bias:** pass domain terms (IaPapo, Clef, ChatState) to the recognizer as contextual strings or a custom language model. Support for SpeechTranscriber is undocumented, so measure it on real audio first.
- **Normalization:** a post-processing map from known misrecognitions to canonical terms (Chaat → CHAT).

### Feedback

State transitions tirgger e.g., `VAEvents(verb:.notifyu, noun:("state-idle"))` that are emitted to trigger user feedback.

### Decisions
- Remote client required: iPhone, iPad, and the M4 Mac can each act as voice agent front end.
- Language split: dedicated SwiftUI iOS/iPadOS app (runnable on macOS). If Typescript is used it will be orchestrated via Swift.
- Each device runs its own state machine. Wake-word detection and STT runs on-device.
- Foreground only: we assume the app is in the foreground for the whole duration of the chat.
- Listen timer resets on transcribed text change, not on raw microphone energy.

### Open Issues
- Mute behavior across states (a mute word moves SPEAKING to IDLE).
- Self-echo: whether Clef must distinguish IaPapo's own output from user speech.
- Whether Clef's labels are per-state or shared.
- How prompt types drive transitions. Clef returns a probability per class and a confidence, so the threshold for fallback is open (see above).
- Whether planPrompt is dropped or kept under another name.
- Purpose of actionPrompt and explainPrompt.
- Clef's access to history.
- Confirmation rules for pi-coding-agent actions.
- Cloud call logging scope.
- Clef prompt-class fallback: below what confidence does Clef's answer fall back to unknownPrompt?
- On-device wake-word engine: Apple speech APIs or a small bundled model. Trade-offs: accuracy, battery, privacy.

### Glossary
- IaPapo: project name as well as default VA name and wake word.
- Voice Assistant (VA): a sync-duplex local chat agent
- Clef: trial decision model and router. Classifies raw STT into prompt types, using the current state machine. Served as `clef-flash-4bit` by the oMLX server at `localhost:7235` on the M4, through its `/v1/decisions` API. It is not a chat model and rejects `/v1/chat/completions`. Each answer carries a probability per class and a confidence.
- Prompt types: syncPrompt (a definitional prompt dedicated to aligning chat context between human and agent), actionPrompt, explainPrompt. A decision model classifies prompt types to guide state transitions. Purpose of actionPrompt and explainPrompt to be defined. The set is not fixed.
- Duplex: in hal-duplex, listening/speaking alternate strictly in turn. With full duplex, the microphone is often live even when the speaker is active. The mic is live so that it can trigger a state change. Standard full-duplex relies on arbtitrary "barge-in". Sync-duplex restricts the barge-in to key phrases (e.g., wakeWord, idleWord)
- Foreground: for simplicity iaPapo Voice Assistant is only interactive when the app is in the foreground. When the app is no longer in the foreground, the ChatState should be INACTIVE. Background VA is out of scope for now. 
- ChatStates (tactical, not final): INACTIVE, IDLE, LISTENING, THINKING, SPEAKING.
- Development: for experiments we have M5 Pro 64GB running oMLX as main local inference LLM; M4 Pro 64GB for desktop premium local voice assistant and decision model testing; iPhone 17  iOS 27 and iPad Pro M4 iOS 27 for mobile voice assistant testing.
- InputState: the state of the microphone: ON, OFF.
- OutputState: the state of the speech: play time-remaining in seconds
- VAQ: the quality of a voice agent (VAQ) is measured by inverse of the number of words taken for synchronizing the understanding of chat participants for a given benchmark topic.
- Implementation: Swift app for Apple HW/SW integration. TypeScript codebase exists and is costly to translate. pi-coding-agent refers to the TypeScript version (@earendil-works/pi-coding-agent); Rust is not used.

