# MCAT Speedrun — AI Note (Friday)

**Exam:** MCAT (472–528; four sections 118–132).
**Provider/model:** OpenAI `gpt-4o-mini` via a stdlib HTTPS call (`pylib/anki/mcat/ai.py`).

## What AI we built, and why

AI is **on by default** and fully toggleable in Account settings (`ai_enabled`,
synced across desktop + iOS). With the toggle **off, the app makes zero model
calls** and behaves exactly like the Wednesday no-AI build — and still produces
all three scores. This satisfies the rule that both apps run and score with AI
switched off.

Three AI features, each **grounded in a named source** and each with a
**deterministic non-AI fallback**:

1. **Reasoning feedback (performance practice).** On the second pass over missed
   questions, the student must *argue* their answer in free text. After
   submitting, the model grades that argument — `sound` / `partially_sound` /
   `flawed` — with 2–3 sentences of feedback and a key takeaway.
   *Source:* the question's own official **answer explanation** (shown to the
   user as `Source: Official answer explanation`). The model is instructed to
   judge only against that explanation, not outside facts.

2. **CARS debate.** With AI on, CARS practice becomes an interactive debate: the
   student argues, and the model role-plays the **passage author** defending the
   claim, plus a one-line coaching critique of the student's reasoning skill.
   *Source:* the **passage text** (`Source: Passage text`); the model may use
   only reasoning grounded in the passage.

3. **Study coach.** The dashboard shows one recommendation for the single best
   next action (prerequisite flashcards vs. targeted performance practice in a
   named section). *Source:* the student's **measured scores**
   (`Source: Your measured scores`) — coverage %, memory recall, and first-answer
   performance per section, which already fold in certainty and combined
   cross-device study.

## What we skipped (deliberately)

- **AI card generation** is not shipped. It's the highest-risk AI surface (wrong
  facts), and the Friday features above are the ones the product needs. The
  `tools/mcat/leakage_check.py` guard and the eval pattern here are the
  foundation for adding generation safely later.
- **iOS AI interactions** are desktop-first for now. The toggle syncs to iOS and
  the shared study log/scoring already sync; the iOS AI UI (debate/feedback) is
  the next step. Friday's AI deliverables are desktop, and iOS already meets the
  Friday mobile bar (two-way sync, offline, three scores + give-up rule).
- **No key on device.** The key lives only in a gitignored local file
  (`pylib/anki/mcat/.openai_key`) or the `OPENAI_API_KEY` env var, never in the
  repo. A Firebase Function proxy is the planned production path so the iOS
  bundle never carries a key.

## Traceability (every AI output names its source)

Each AI response object carries a `source` field that the UI renders verbatim
("Source: …"). The prompt for each feature embeds exactly that source and
instructs the model to stay within it. No AI output is shown without a source.

## Evaluation (held-out, re-runnable, beats a baseline)

The reasoning grader is the scored AI model. It's evaluated on a **held-out gold
set** (`tools/mcat/eval_data/reasoning_gold.json`, 20 hand-labeled arguments)
that **never appears in any prompt** — a true held-out test.

Run it (reproducible by anyone with a key):

```
OPENAI_API_KEY=sk-... PYTHONPATH="pylib:out/pylib" \
    out/pyenv/bin/python tools/mcat/eval_reasoning.py
```

**Cutoff (declared before running):** ship only if exact-label accuracy ≥ 70%
**and** flawed-missed rate ≤ 20% (never praise genuinely wrong reasoning) **and**
it beats the baseline.

**Baseline:** a transparent keyword-overlap (Jaccard) classifier — no LLM.

**Result (gpt-4o-mini):**

| metric               | AI grader | keyword baseline |
| -------------------- | --------- | ---------------- |
| exact-label accuracy | 100%      | 55%              |
| flawed-missed rate   | 0%        | 25%             |

→ **PASS** — beats baseline on both metrics and clears the cutoff.

## Leakage

The gold set is authored separately from the app's content pack and is never
sent to the model as few-shot examples or context (the grader sees only the
single item under test). `tools/mcat/leakage_check.py` guards the content
pipeline against train/test overlap for the broader system.

## Robustness / AI-off behavior

- Any network error, timeout, or unparseable response returns `None`; the caller
  falls back to the deterministic experience (show the explanation; classic CARS
  prompts; no coach card). AI never blocks or crashes a session.
- Responses are cached in the collection config by a hash of model+prompt, so
  re-opening a review is instant, works offline, and doesn't re-bill the API.
- Turning the toggle off stops all calls immediately and restores the exact
  non-AI flows.
