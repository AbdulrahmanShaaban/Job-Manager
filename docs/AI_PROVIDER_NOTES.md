# AI provider notes — strict $0 operation

The voice assistant is the riskiest part of this product: it is the only piece
that depends on third-party services whose free terms can change without notice,
and it is the only place where client business data leaves the database.

> **Verified against the live Gemini service on 2026-10-26:** a real key minted
> an ephemeral token (`POST /voice/session-credential` → 201) and the WebSocket
> handshake reached `setupComplete` plus `sessionResumptionUpdate` with the
> server-issued setup. Model IDs `gemini-3.8-live` and `gemini-3.5-flash` were
> confirmed for that key.
>
> **Still unverified:** an actual Arabic audio turn (speech recognition accuracy
> and reply quality), Groq (no key, so the fallback chain is inert), latency under
> real network conditions, and behaviour at the real free-tier quota boundary.

---

## 1. Why the architecture looks like this

Hard requirements from the spec:

1. The permanent provider key must never be in the Flutter app.
2. No paid API call may happen by accident.
3. Every write the assistant proposes must be a draft until the user confirms.
4. When every free provider is exhausted, the app must degrade to manual entry
   without losing the user's text.

That produces three layers:

```
Flutter                          Server                        Provider
─────────────────────────────────────────────────────────────────────────
Live mode:   ephemeral token ──▶ /voice/session-credential ──▶ Gemini authTokens
             WSS + audio  ──────────────────────────────────▶ Gemini Live
             tool calls   ──▶ /voice/tool ──▶ validated DB access

Fallback:    short audio  ──▶ /voice/fallback-turn ──▶ Groq Whisper → text LLM
             text reply   ◀────────────────────────── (device TTS)
```

The Flutter client never sees `GEMINI_API_KEY` or `GROQ_API_KEY`. It only
receives a single-use, 30-minute token bound to one model and one config.

---

## 2. Live mode (primary)

### 2.1 Credential issuance

`POST /api/v1/voice/session-credential` → `createLiveCredential()` in
`src/modules/voice/gemini-live.ts`:

- Creates a `VoiceSession` row (`provider: GEMINI_LIVE`, `status: ACTIVE`).
- Calls `ai.authTokens.create({ uses: 1, expireTime, newSessionExpireTime,
  liveConnectConstraints })`.
- Returns `{ token, model, setup, expiresAt, newSessionExpireTime,
  maxSessionSeconds, transcriptRetentionEnabled }`.

`liveConnectConstraints` locks the token to `GEMINI_LIVE_MODEL` and the exact
generation config, so a stolen token cannot be re-pointed at another model.

The `setup` object is built by `buildClientSetup()` in
`src/modules/voice/prompt.ts` and is sent verbatim by the client as the first
WebSocket message.

### 2.2 Wire protocol used by the client

Endpoint:

```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=<token>
```

**The `Constrained` suffix is mandatory for ephemeral tokens.** Connecting to
`...BidiGenerateContent` with an `auth_tokens/...` value closes the socket with
`1008 Method doesn't allow unregistered callers`, which looks like an invalid
key but is really the wrong method: the plain method only accepts an API key.
The same token then succeeds on `BidiGenerateContentConstrained`. Verified
against the live service on 2026-10-26.

Messages:

| Direction | Payload |
| --- | --- |
| → | `{"setup": <credential.setup>}` |
| → | `{"realtimeInput":{"audio":{"mimeType":"audio/pcm;rate=16000","data":"<base64 PCM16 mono>"}}}` |
| ← | `{"serverContent":{"inputTranscription":{"text":"..."}}}` |
| ← | `{"serverContent":{"outputTranscription":{"text":"..."}}}` |
| ← | `{"toolCall":{"functionCalls":[{"id":"...","name":"prepareVisitDraft","args":{...}}]}}` |
| → | `{"toolResponse":{"functionResponses":[{"id":"...","name":"...","response":{"result":{...}}}]}}` |

Audio in is 16 kHz, mono, signed 16-bit little-endian PCM. Audio **out** is not
requested: `responseModalities` is `["TEXT"]`, and the device speaks the reply
with `flutter_tts`. This avoids depending on a paid/limited audio-output path and
keeps bandwidth down on a site with weak signal.

### 2.3 Tool calls are server-side only

The model never talks to the database. When it emits a `toolCall`, the Flutter
client forwards it to `POST /api/v1/voice/tool`, which:

1. Rejects unknown tool names (`z.enum(TOOL_NAMES)`).
2. Validates `args` against a per-tool Zod schema (`argsSchemas` in
   `tool-actions.ts`).
3. Re-checks site/task access with `requireSiteAccess` / `requireTaskAccess`
   for the authenticated user.
4. Returns `{ ok: true, result }`.

Draft tools (`prepareVisitDraft`, `prepareTaskDraft`, `prepareTaskUpdate`) only
read data and return `requiresConfirmation: true`. They never write.

### 2.4 Model IDs are configuration, not constants

| Variable | Default in `.env.example` | Re-verify before release |
| --- | --- | --- |
| `GEMINI_LIVE_MODEL` | `gemini-3.8-live` | Current Live-capable model ID, release state, free-tier availability |
| `GEMINI_TEXT_MODEL` | `gemini-3.5-flash` | Current Flash model, free tier, Arabic quality |

Both are plain strings in the environment. Nothing in the code assumes a model
family beyond "supports Live with function calling" and "supports
`generateContent` with `responseMimeType: application/json`".

**Before you ship:** open the official Live API docs, the pricing page, the
ephemeral-token docs, and the session-management docs, and confirm for the
current date:

- the exact supported model ID and whether it is GA or preview;
- free-tier request/minute and token/minute limits;
- whether the free tier is permitted for commercial use of client data;
- data-use terms (is free-tier traffic used for training?);
- whether ephemeral tokens and `liveConnectConstraints` are still supported in
  this shape;
- session length limits and whether `sessionResumption` is still the right knob.

If any answer is "no" or "unclear", change the model or disable Live and rely on
the fallback. Do not guess.

---

## 3. Fallback mode

`POST /api/v1/voice/fallback-turn` accepts a raw audio body
(`audio/*` or `application/octet-stream`), capped by `AI_FALLBACK_MAX_BYTES`
(default 6 MiB) with a duration cap of `AI_FALLBACK_MAX_SECONDS` (default 20 s).

Pipeline in `src/modules/voice/fallback-pipeline.ts`:

1. `assertAiBudget()` — refuses if the monthly session or minute soft limit is
   already reached (`429 AI_QUOTA_EXHAUSTED`).
2. Create a `VoiceSession` row (`provider: FALLBACK`).
3. **STT** — Groq Whisper first (`GROQ_STT_MODEL`), then Gemini
   (`GEMINI_TEXT_MODEL`) with an Arabic transcription instruction.
4. **Context** — `buildAssistantContext()` lists up to 40 accessible sites with
   IDs and open-task counts. This is the only site data sent to the text model.
5. **Plan** — Gemini or Groq, constrained to JSON:
   `{"reply": "...", "tool": {"name": "...", "args": {...}} | null}`.
6. **Act** — if a tool was chosen, `executeTool()` validates and runs it.
7. **Compose** — a second model call turns the raw tool result into 2–3
   Egyptian-Arabic sentences. On failure it falls back to the first draft reply.
8. **TTS** — device-side TTS on the phone. The server returns text only; the
   optional Azure Speech path was removed because it requires a credit card.
9. Update the session row with status, model IDs, estimated seconds, and the
   transcript **only if** `TRANSCRIPT_RETENTION_ENABLED=true`.

Nothing in this path retries in a loop: `tryProviders()` walks a fixed list, at
most one attempt per provider, and marks a cooldown on failure.

### 3.0 Client-side handling

- The recorded WAV is written to the temporary directory and deleted in a
  `finally` block after the turn is uploaded, whether the upload succeeded or
  failed.
- One countdown timer owns the recording stop; the tap handler and the timer
  cannot both submit the same turn.
- When the user confirms a visit draft and `keepTranscripts` is on (and the
  server has `TRANSCRIPT_RETENTION_ENABLED=true`), the client sends the user's
  own lines from that session as `transcript`. Otherwise it sends nothing.

### 3.1 Provider cooldowns

`provider-router.ts` keeps an in-process map:

| Failure | Cooldown | Effect |
| --- | --- | --- |
| `429` / quota / `RESOURCE_EXHAUSTED` | 15 min | Provider skipped |
| `401` / `403` | 60 s | Provider skipped |
| `5xx` or network | 60 s | Provider skipped |
| Other | no cooldown | Next provider tried immediately |

Cooldowns are per-process and reset on restart. With a single API instance that
is fine; if you scale to multiple instances, each has its own map, so a provider
outage is discovered once per instance. That is acceptable for this MVP and is
deliberately not backed by Redis (forbidden by the spec).

`GET /api/v1/voice/usage` exposes the current cooldown snapshot so the app can
explain why voice is unavailable.

---

## 4. The zero-cost guards

| Guard | Where | Behaviour |
| --- | --- | --- |
| `AI_ALLOW_PAID_FALLBACK=false` | `env.ts` + `assertFreeOnlyMode()` | `true` throws at boot in production and at call time elsewhere |
| `AI_MONTHLY_BUDGET_USD=0` | reported by `/voice/usage` | Displayed, never used to authorise spend |
| `AI_MAX_SESSION_SECONDS` | credential payload | Client stops the Live session at this cap |
| `AI_MONTHLY_SESSION_LIMIT` / `AI_MONTHLY_MINUTES_LIMIT` | `assertAiBudget()` | Soft local limits; `429 AI_QUOTA_EXHAUSTED` when reached |
| Provider cooldowns | `provider-router.ts` | Prevents hammering an exhausted free tier |
| No retry loop | `tryProviders()` | One attempt per provider per request |

The budget number is intentionally informational. There is no code path that
converts it into a paid call; enabling paid usage requires editing
`assertFreeOnlyMode()` **and** the production boot check — i.e. an explicit code
change, which is what the spec asks for.

### 4.1 What the user sees when everything is exhausted

The app distinguishes:

- `AI_UNAVAILABLE` (503) — not configured, or the provider is down. The mic
  action shows "المساعد مش متاح دلوقتي" and offers manual entry.
- `AI_QUOTA_EXHAUSTED` (429) — free limits reached. The message says the draft is
  safe and points at manual entry.
- Client-side network failure — the recorded text and any draft stay on screen.

In all three cases the draft is preserved and the manual visit/task forms remain
reachable. The app never implies unlimited free voice.

---

## 5. Data handling and privacy

| Data | Where it goes | Retention |
| --- | --- | --- |
| Audio (Live) | Streamed to Gemini, not stored server-side | Not retained |
| Audio (fallback) | Sent to Groq/Gemini for STT, held in memory | Not retained; the buffer is discarded after the request |
| Transcript | Returned to the device; stored in `VoiceSession` only if retention is on | Off by default |
| Site names/IDs + open-task counts | Included in the text-model context | Not stored by us |
| Drafts | Returned to the device for review | Only stored when the user confirms |
| Provider keys | Server env only | Never sent to the client, never logged |

Before enabling voice for real client data, confirm each provider's current
free-tier data-use terms. If a provider trains on free-tier input, do not send
site names, addresses, or client notes there — disable that provider and keep
manual entry.

---

## 6. Swap-in points

If a provider changes terms, disappears, or is replaced:

| Goal | File | Function |
| --- | --- | --- |
| Change the Live model | `.env` | `GEMINI_LIVE_MODEL` |
| Change the text model | `.env` | `GEMINI_TEXT_MODEL` |
| Add a new STT provider | `fallback-pipeline.ts` | push into `attempts` inside `transcribe()` |
| Add a new text LLM | `fallback-pipeline.ts` | push into `attempts` inside `planTurn()` / `composeReply()` |
| Replace TTS | `fallback-pipeline.ts` | `synthesizeArabic()` |
| Add a new assistant action | `tool-actions.ts` + `prompt.ts` | `TOOL_NAMES`, `argsSchemas`, `TOOL_DECLARATIONS` |
| Change the persona/rules | `prompt.ts` | `buildSystemInstruction()`, `fallbackSystemPrompt()` |

Adding a tool requires three edits in lockstep: the `TOOL_NAMES` tuple, the Zod
schema in `argsSchemas`, and the `FunctionDeclaration` in `TOOL_DECLARATIONS`.
The `satisfies Record<ToolName, z.ZodType>` on `argsSchemas` makes a missing
schema a type error.

---

## 7. Acceptance tests to run with real keys

These are the tests that decide whether the model is good enough. None have been
run.

### 7.1 Live mode, quiet room

- "أنا في موقع النيل بلازا، خلصت تركيب 12 كاميرا، فاضل 4 كاميرات وشبكة السيرفر."
- Expect: `searchSites` → site match → `prepareVisitDraft` with the right site,
  today's Cairo date, 12/4 in the correct fields → reads it back → asks
  "أأكد الحفظ؟" → no save until confirmed in the UI.
- Then confirm in the review sheet and verify exactly one visit row is created.

### 7.2 Ambiguity

- Two sites named "النيل": "أنا في النيل" → the assistant must ask which one and
  must not pick arbitrarily.

### 7.3 Numbers and dates

- "الزيارة كانت يوم ٢٨ فبراير" in a non-leap year → must reject or ask, not
  silently store 1 March.
- "خمستاشر كاميرا" vs "خمسين كاميرا" → must read the number back before saving.

### 7.4 Noisy site

- Record with background drilling/traffic. Check whether STT drops numbers. If it
  does, the read-back rule is the mitigation, not a louder prompt.

### 7.5 Quota behaviour

- Use up the free tier deliberately on a test key. Confirm: Live returns
  `AI_QUOTA_EXHAUSTED`, the app offers fallback, fallback also returns
  `AI_QUOTA_EXHAUSTED`, and manual entry still works with the draft intact.
- Restart the API and confirm the cooldown map resets (expected).

### 7.6 Offline

- Airplane mode → open voice → confirm it fails fast with a network message, not
  a spinner that never ends, and that the manual visit form still works.

### 7.7 Transcript retention

- With `TRANSCRIPT_RETENTION_ENABLED=false`, complete a session and confirm
  `VoiceSession.transcript` is `NULL` in the database.
- Flip it to `true`, restart, repeat, confirm the transcript is stored and that
  the Settings screen reflects the new state.

---

## 8. Known gaps in this build

- **`VoiceSession.modelId` is imprecise for fallback turns.** It is composed from
  `GROQ_STT_MODEL` and `GEMINI_TEXT_MODEL` regardless of which provider actually
  served the request. The `provider` field on the response is accurate; the
  stored `modelId` string can be misleading. Fix by returning the model ID from
  each provider call.
- Cooldowns are per-process and in-memory.
- No cost/usage meter beyond session count and estimated seconds — the spec
  forbids pricing features, so this is a deliberate ceiling.
- No automated test covers the Live WebSocket protocol; it is exercised only by
  the device at runtime.
- Azure Speech TTS is intentionally absent. It was the only provider that
  required a credit card, and device TTS covers the same need for free.
