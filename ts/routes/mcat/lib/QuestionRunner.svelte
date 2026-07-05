<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The Performance Set / Section Practice engine: first-pass answering with a
required confidence label and a per-item countdown, delayed batch feedback (no
per-question reveal until the second pass), then second-pass reasoning. All
correctness is decided on the backend.
-->
<script lang="ts">
    import { createEventDispatcher, onDestroy, onMount } from "svelte";
    import { fly } from "svelte/transition";

    import { postJson } from "./api";
    import Content from "./Content.svelte";
    import Mascot from "./Mascot.svelte";
    import { CONFIDENCE_LABELS, SECTION_NAMES } from "./types";
    import type { FirstPassResponse, QuestionBatch, RevealResult } from "./types";

    export let batch: QuestionBatch;
    export let phase = "daily";
    export let label = "Performance Set";
    export let accent = "var(--mcat-amber)";
    export let seconds = 120;
    // When AI is on, the second pass asks the student to argue their answer, and
    // results carry personalized reasoning feedback.
    export let aiEnabled = false;
    // The diagnostic sets this false: a single pass, no "take another look".
    export let allowSecondPass = true;

    const dispatch = createEventDispatcher<{ complete: { results: RevealResult[] } }>();

    type FirstAnswer = {
        choice: string;
        confidence: string;
        time_ms: number;
        over_time: boolean;
    };
    type SecondAnswer = { choice: string; reasoning: string };

    let stage: "first" | "feedback" | "second" | "results" = "first";
    let idx = 0;
    const firstAnswers: Record<number, FirstAnswer> = {};
    const secondAnswers: Record<number, SecondAnswer> = {};
    let firstResp: FirstPassResponse | null = null;
    let results: RevealResult[] = [];
    let busy = false;

    // Review flow: a grid overview, then a per-question walk-through with an
    // AI concept title + diagram + minimal text (rather than a wall of cards).
    type ConceptCard = { svg: string | null; title: string | null };
    let reviewMode = false;
    let reviewIdx = 0;
    let showQ = false;
    // Every question must be looked at (right and wrong) before finishing.
    let viewed = new Set<number>();
    let cardByNote: Record<number, ConceptCard> = {};
    // Note ids whose diagram is currently being generated (drives the loader).
    let loadingNotes = new Set<number>();

    let curChoice = "";
    let curConfidence = "";
    let curReasoning = "";
    let questionStart = Date.now();

    // Per-item countdown.
    let timeLeft = seconds;
    let timerId: ReturnType<typeof setInterval> | undefined;
    onMount(() => {
        timerId = setInterval(() => {
            // Count into overtime (negative) rather than stopping — we never
            // auto-skip; going long just flags the question (fed to the coach).
            if (stage === "first" || stage === "second") {
                timeLeft -= 1;
            }
        }, 1000);
    });
    onDestroy(() => clearInterval(timerId));
    function resetTimer(): void {
        timeLeft = seconds;
    }
    $: overtime = timeLeft < 0;
    $: mmss = overtime
        ? `+${Math.floor(-timeLeft / 60)}:${String(-timeLeft % 60).padStart(2, "0")}`
        : `${Math.floor(timeLeft / 60)}:${String(timeLeft % 60).padStart(2, "0")}`;

    $: total = batch.questions.length;
    $: q = batch.questions[idx];
    $: progressPct = total ? (idx / total) * 100 : 0;
    $: firstRight = results.filter((r) => r.first_correct).length;
    $: cur = results[reviewIdx] ?? null;
    $: curCard = cur ? cardByNote[cur.note_id] : undefined;
    $: curSvg = curCard?.svg ?? null;
    $: curTitle = curCard?.title ?? null;
    $: curLoading = cur ? loadingNotes.has(cur.note_id) : false;
    $: allViewed = results.length > 0 && results.every((r) => viewed.has(r.note_id));

    $: wrongCount = firstResp?.wrong_count ?? 0;
    $: changedCount = countChanged(curChoice, idx, secondAnswers);

    function countChanged(
        _cur: string,
        _i: number,
        _committed: Record<number, SecondAnswer>,
    ): number {
        let n = 0;
        for (let j = 0; j < batch.questions.length; j++) {
            const noteId = batch.questions[j].note_id;
            const first = firstAnswers[noteId]?.choice ?? "";
            const second =
                j === idx ? curChoice : (secondAnswers[noteId]?.choice ?? "");
            if (second && second !== first) {
                n += 1;
            }
        }
        return n;
    }

    function resetCurrent(): void {
        curChoice = "";
        curConfidence = "";
        questionStart = Date.now();
        resetTimer();
    }

    async function nextFirst(): Promise<void> {
        if (!curChoice || !curConfidence) {
            return;
        }
        const elapsed = Date.now() - questionStart;
        firstAnswers[q.note_id] = {
            choice: curChoice,
            confidence: curConfidence,
            time_ms: elapsed,
            over_time: elapsed > seconds * 1000,
        };
        if (idx + 1 < total) {
            idx += 1;
            resetCurrent();
        } else {
            await submitFirst();
        }
    }

    async function submitFirst(): Promise<void> {
        busy = true;
        try {
            const answers = batch.questions.map((item) => ({
                note_id: item.note_id,
                ...firstAnswers[item.note_id],
            }));
            firstResp = await postJson<FirstPassResponse>("mcatSubmitFirst", {
                batch_id: batch.batch_id,
                phase,
                single_pass: !allowSecondPass,
                answers,
            });
            if (firstResp.reveal) {
                results = firstResp.results ?? [];
                stage = "results";
            } else {
                stage = "feedback";
            }
        } finally {
            busy = false;
        }
    }

    function startSecond(): void {
        stage = "second";
        idx = 0;
        for (const item of batch.questions) {
            secondAnswers[item.note_id] = {
                choice: firstAnswers[item.note_id]?.choice ?? "",
                reasoning: "",
            };
        }
        curChoice = secondAnswers[batch.questions[idx].note_id]?.choice ?? "";
        curReasoning = "";
        resetTimer();
    }

    async function nextSecond(): Promise<void> {
        if (!curChoice) {
            return;
        }
        // With AI on, require a short argument so the reasoning feedback is real.
        if (aiEnabled && curReasoning.trim().length < 3) {
            return;
        }
        secondAnswers[batch.questions[idx].note_id] = {
            choice: curChoice,
            reasoning: curReasoning.trim(),
        };
        if (idx + 1 < total) {
            idx += 1;
            const saved = secondAnswers[batch.questions[idx].note_id];
            curChoice = saved?.choice ?? "";
            curReasoning = saved?.reasoning ?? "";
            resetTimer();
        } else {
            await submitSecond();
        }
    }

    // Go back to the previous question (keeps the current partial answer).
    function prevFirst(): void {
        if (idx === 0) {
            return;
        }
        const qNow = batch.questions[idx];
        if (curChoice) {
            const elapsed = Date.now() - questionStart;
            firstAnswers[qNow.note_id] = {
                choice: curChoice,
                confidence: curConfidence,
                time_ms: elapsed,
                over_time: elapsed > seconds * 1000,
            };
        }
        idx -= 1;
        const saved = firstAnswers[batch.questions[idx].note_id];
        curChoice = saved?.choice ?? "";
        curConfidence = saved?.confidence ?? "";
        questionStart = Date.now();
        resetTimer();
    }

    function prevSecond(): void {
        if (idx === 0) {
            return;
        }
        secondAnswers[batch.questions[idx].note_id] = {
            choice: curChoice,
            reasoning: curReasoning.trim(),
        };
        idx -= 1;
        const saved = secondAnswers[batch.questions[idx].note_id];
        curChoice = saved?.choice ?? "";
        curReasoning = saved?.reasoning ?? "";
        resetTimer();
    }

    async function submitSecond(): Promise<void> {
        busy = true;
        try {
            const answers = batch.questions.map((item) => ({
                note_id: item.note_id,
                choice: secondAnswers[item.note_id]?.choice ?? "",
                reasoning: secondAnswers[item.note_id]?.reasoning ?? "",
            }));
            const resp = await postJson<{ results: RevealResult[] }>(
                "mcatSubmitSecond",
                {
                    batch_id: batch.batch_id,
                    answers,
                },
            );
            results = resp.results;
            stage = "results";
        } finally {
            busy = false;
        }
    }

    function questionById(noteId: number): string {
        const found = batch.questions.find((item) => item.note_id === noteId);
        return found ? found.question : "";
    }

    function questionChoices(noteId: number): { key: string; text: string }[] {
        return batch.questions.find((item) => item.note_id === noteId)?.choices ?? [];
    }

    function labelText(label2: string | null | undefined): string {
        return label2 ? label2.replace(/_/g, " ") : "";
    }

    function firstPick(noteId: number): string {
        return firstAnswers[noteId]?.choice ?? "";
    }

    type Verdict = "correct" | "shaky" | "missed";
    function verdictOf(r: RevealResult): Verdict {
        const aiv = r.ai_feedback?.verdict;
        if (r.first_correct) {
            return aiv === "flawed" || aiv === "partially_sound" ? "shaky" : "correct";
        }
        return r.second_correct ? "shaky" : "missed";
    }
    const VERDICT_TEXT: Record<Verdict, string> = {
        correct: "Correct",
        shaky: "Shaky reasoning",
        missed: "Missed",
    };

    async function loadCard(r: RevealResult | null): Promise<void> {
        if (
            !aiEnabled ||
            !r ||
            r.note_id in cardByNote ||
            loadingNotes.has(r.note_id)
        ) {
            return;
        }
        loadingNotes = new Set(loadingNotes).add(r.note_id);
        try {
            const resp = await postJson<ConceptCard>("mcatConceptSvg", {
                note_id: r.note_id,
            });
            cardByNote = {
                ...cardByNote,
                [r.note_id]: { svg: resp.svg, title: resp.title },
            };
        } catch {
            cardByNote = {
                ...cardByNote,
                [r.note_id]: { svg: null, title: null },
            };
        } finally {
            const s = new Set(loadingNotes);
            s.delete(r.note_id);
            loadingNotes = s;
        }
    }

    function markViewed(i: number): void {
        const r = results[i];
        if (r) {
            viewed = new Set(viewed).add(r.note_id);
        }
    }
    function firstUnviewed(): number {
        const i = results.findIndex((r) => !viewed.has(r.note_id));
        return i < 0 ? 0 : i;
    }
    function keyLine(r: RevealResult): string {
        if (r.ai_feedback && (r.ai_feedback.key_point || r.ai_feedback.feedback)) {
            return r.ai_feedback.key_point || r.ai_feedback.feedback;
        }
        return r.explanation ?? "";
    }
    function sourceLine(r: RevealResult): string {
        return r.ai_feedback
            ? `Source: ${r.ai_feedback.source}`
            : "Grounded in the official explanation";
    }
    function startReview(i: number): void {
        reviewMode = true;
        reviewIdx = i;
        showQ = false;
        markViewed(i);
        loadCard(results[i]);
    }
    function reviewGo(delta: number): void {
        const next = reviewIdx + delta;
        if (next < 0 || next >= results.length) {
            return;
        }
        reviewIdx = next;
        showQ = false;
        markViewed(next);
        loadCard(results[next]);
    }
</script>

<div class="runner" style={`--accent:${accent}`}>
    {#if stage === "first" || stage === "second"}
        <div class="rhead">
            <span class="rtag">
                <span class="dot"></span>
                {label} · {SECTION_NAMES[q.section] ?? q.section} · Item {idx + 1} Of {total}
            </span>
            <span
                class="timer"
                class:low={!overtime && timeLeft <= 10}
                class:over={overtime}
            >
                {#if overtime}<span class="over-tag">Over</span>{/if}{mmss}
            </span>
        </div>
        <div class="pbar"><span style={`width:${progressPct}%`}></span></div>

        <div class="qrow">
            {#key idx}
                <div class="mcat-card question" in:fly={{ x: 24, duration: 240 }}>
                    <div class="qtext"><Content text={q.question} /></div>
                    <div class="choices">
                        {#each q.choices as choice (choice.key)}
                            <label
                                class="choice"
                                class:selected={curChoice === choice.key}
                            >
                                <input
                                    type="radio"
                                    name={`q-${q.note_id}-${stage}`}
                                    value={choice.key}
                                    bind:group={curChoice}
                                />
                                <span class="ck">{choice.key}</span>
                                <span class="ctext">
                                    <Content text={choice.text} inline />
                                </span>
                                {#if stage === "second" && firstPick(q.note_id) === choice.key}
                                    <span class="firstpick">First pick</span>
                                {/if}
                            </label>
                        {/each}
                    </div>

                    {#if stage === "first"}
                        <div class="conf">
                            <div class="conf-label">
                                How Confident Are You In This Answer?
                            </div>
                            <div class="seg">
                                {#each CONFIDENCE_LABELS as c (c.key)}
                                    <button
                                        type="button"
                                        class="seg-btn"
                                        class:on={curConfidence === c.key}
                                        on:click={() => (curConfidence = c.key)}
                                    >
                                        {c.label}
                                    </button>
                                {/each}
                            </div>
                        </div>
                    {:else if aiEnabled}
                        <div class="reasoning">
                            <label class="reasoning-label" for="reasoning">
                                Argue your answer — why is it right?
                            </label>
                            <textarea
                                id="reasoning"
                                class="reasoning-input"
                                rows="3"
                                bind:value={curReasoning}
                                placeholder="Explain your reasoning. Your coach will respond to this."
                            ></textarea>
                        </div>
                    {:else}
                        <p class="second-hint">
                            Second pass — take another look and lock in your final
                            answer.
                        </p>
                    {/if}

                    <div class="actions">
                        {#if idx > 0}
                            <button
                                class="mcat-btn back-btn"
                                on:click={stage === "first" ? prevFirst : prevSecond}
                            >
                                ← Back
                            </button>
                        {/if}
                        <button
                            class="mcat-btn mcat-btn-primary"
                            disabled={busy ||
                                !curChoice ||
                                (stage === "first"
                                    ? !curConfidence
                                    : aiEnabled && curReasoning.trim().length < 3)}
                            on:click={stage === "first" ? nextFirst : nextSecond}
                        >
                            {idx + 1 < total ? "Submit & Next" : "Submit Response"}
                        </button>
                    </div>
                </div>
            {/key}

            {#if stage === "second"}
                <aside class="side">
                    <div class="side-title">Second Pass</div>
                    <div class="side-stat bad">
                        <span class="side-num">{wrongCount}</span>
                        <span class="side-label">to fix from pass 1</span>
                    </div>
                    <div class="side-stat">
                        <span class="side-num">{changedCount}</span>
                        <span class="side-label">answers changed</span>
                    </div>
                    <p class="side-note">
                        Re-decide each one and explain your final choice.
                    </p>
                </aside>
            {/if}
        </div>
    {:else if stage === "feedback"}
        <div class="mcat-card feedback">
            <div class="fb-title">One More Pass Before The Answers</div>
            <p>{firstResp?.message}</p>
            <button class="mcat-btn mcat-btn-primary" on:click={startSecond}>
                Take Another Look
            </button>
        </div>
    {:else if !reviewMode}
        <div class="results overview">
            <div class="rv-intro">
                <Mascot
                    size={82}
                    mood={firstRight >= results.length / 2 ? "happy" : "neutral"}
                />
                <div class="rv-score">
                    {firstRight} of {results.length} on first try
                </div>
                <div class="rv-sub">
                    Let's walk through them together — one at a time.
                </div>
            </div>

            <div class="mcat-card rv-grid-card">
                <div class="rv-grid-title">Tap a question to review</div>
                <div class="rv-grid">
                    {#each results as r, i (r.note_id)}
                        <button
                            class="tile {verdictOf(r)}"
                            class:seen={viewed.has(r.note_id)}
                            in:fly={{ y: 14, duration: 240, delay: i * 35 }}
                            on:click={() => startReview(i)}
                        >
                            <span class="tile-num">{i + 1}</span>
                            <span class="tile-mark">
                                {#if viewed.has(r.note_id)}✓{/if}
                            </span>
                        </button>
                    {/each}
                </div>
                <div class="rv-legend">
                    <span class="lg correct">
                        <i></i>
                        Correct
                    </span>
                    <span class="lg shaky">
                        <i></i>
                        Shaky reasoning
                    </span>
                    <span class="lg missed">
                        <i></i>
                        Missed
                    </span>
                </div>
            </div>

            <div class="rv-cta">
                {#if allViewed}
                    <button
                        class="mcat-btn mcat-btn-primary rv-start"
                        on:click={() => dispatch("complete", { results })}
                    >
                        Go to dashboard
                    </button>
                {:else}
                    <button
                        class="mcat-btn mcat-btn-primary rv-start"
                        on:click={() => startReview(firstUnviewed())}
                    >
                        {viewed.size > 0 ? "Continue review" : "Start review"}
                    </button>
                    <p class="rv-hint">
                        Review every question — right and wrong — to finish.
                    </p>
                {/if}
            </div>
        </div>
    {:else if cur}
        <div class="results review">
            {#if showQ}
                <div class="mcat-card qtakeover" in:fly={{ y: 12, duration: 200 }}>
                    <div class="qt-label">
                        Question {reviewIdx + 1} of {results.length}
                    </div>
                    <div class="qt-stem">
                        <Content text={questionById(cur.note_id)} />
                    </div>
                    <div class="qt-choices">
                        {#each questionChoices(cur.note_id) as c (c.key)}
                            <div
                                class="qt-choice"
                                class:correct={c.key === cur.correct}
                            >
                                <span class="qt-ck">{c.key}</span>
                                <span class="qt-text">
                                    <Content text={c.text} inline />
                                </span>
                            </div>
                        {/each}
                    </div>
                    <button
                        class="mcat-btn mcat-btn-primary qt-back"
                        on:click={() => (showQ = false)}
                    >
                        ← Back to feedback
                    </button>
                </div>
            {:else}
                <div class="rv-dots">
                    {#each results as rr, i (rr.note_id)}
                        <button
                            class="dot-seg {verdictOf(rr)}"
                            class:cur={i === reviewIdx}
                            aria-label={`Question ${i + 1}`}
                            on:click={() => startReview(i)}
                        ></button>
                    {/each}
                </div>

                {#key reviewIdx}
                    <div class="mcat-card rv-card" in:fly={{ x: 20, duration: 220 }}>
                        <div class="rv-card-head">
                            <span class="verdict-pill {verdictOf(cur)}">
                                {VERDICT_TEXT[verdictOf(cur)]}
                            </span>
                            <span class="rv-count">
                                {reviewIdx + 1} / {results.length}
                            </span>
                            <Mascot
                                size={40}
                                mood={verdictOf(cur) === "correct"
                                    ? "happy"
                                    : "neutral"}
                            />
                        </div>

                        {#if curTitle}
                            <div class="rv-title">{curTitle}</div>
                        {/if}

                        {#if aiEnabled && curSvg}
                            <!-- eslint-disable-next-line svelte/no-at-html-tags -->
                            <div class="rv-svg">{@html curSvg}</div>
                        {:else if aiEnabled && curLoading}
                            <div class="rv-svg-loading">
                                <span class="gen-dots">
                                    <span></span>
                                    <span></span>
                                    <span></span>
                                </span>
                                <span class="gen-text">Generating diagram…</span>
                            </div>
                        {/if}

                        <div class="rv-answer">
                            <span class="rp answer">Answer {cur.correct}</span>
                            {#if cur.label}
                                <span class="rp">{labelText(cur.label)}</span>
                            {/if}
                        </div>

                        {#if keyLine(cur)}
                            <div class="rv-key"><Content text={keyLine(cur)} /></div>
                        {/if}

                        <button class="rv-q-toggle" on:click={() => (showQ = true)}>
                            Show question
                        </button>

                        <p class="rv-src">{sourceLine(cur)}</p>
                    </div>
                {/key}

                <div class="rv-nav">
                    <button
                        class="mcat-btn pager-btn"
                        disabled={reviewIdx === 0}
                        on:click={() => reviewGo(-1)}
                    >
                        ← Back
                    </button>
                    {#if reviewIdx < results.length - 1}
                        <button
                            class="mcat-btn mcat-btn-primary pager-btn"
                            on:click={() => reviewGo(1)}
                        >
                            Next →
                        </button>
                    {:else if allViewed}
                        <button
                            class="mcat-btn mcat-btn-primary pager-btn"
                            on:click={() => dispatch("complete", { results })}
                        >
                            Done
                        </button>
                    {:else}
                        <button
                            class="mcat-btn mcat-btn-primary pager-btn"
                            on:click={() => startReview(firstUnviewed())}
                        >
                            Review remaining
                        </button>
                    {/if}
                </div>
                <button class="rv-back-all" on:click={() => (reviewMode = false)}>
                    ← All questions
                </button>
            {/if}
        </div>
    {/if}
</div>

<style lang="scss">
    .runner {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .rhead {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
    }
    .rtag {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        font-size: 14px;
        font-weight: 700;
    }
    .rtag .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--accent);
    }
    .timer {
        font-size: 14px;
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        color: var(--accent);
        background: color-mix(in srgb, var(--accent) 14%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--accent) 30%, var(--mcat-border));
        border-radius: 999px;
        padding: 4px 12px;
    }
    .timer.low {
        color: var(--mcat-red);
        background: color-mix(in srgb, var(--mcat-red) 14%, var(--mcat-surface));
        border-color: color-mix(in srgb, var(--mcat-red) 30%, var(--mcat-border));
    }
    /* Over the limit: shine red and pulse. We never auto-skip — this just flags
       that the question ran long (fed to the coach). */
    .timer.over {
        color: #fff;
        background: var(--mcat-red);
        border-color: var(--mcat-red);
        animation: timerPulse 1s ease-in-out infinite;
    }
    .over-tag {
        font-size: 10px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin-right: 6px;
        opacity: 0.9;
    }
    @keyframes timerPulse {
        0%,
        100% {
            box-shadow: 0 0 0 0 color-mix(in srgb, var(--mcat-red) 55%, transparent);
        }
        50% {
            box-shadow: 0 0 0 7px color-mix(in srgb, var(--mcat-red) 0%, transparent);
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .timer.over {
            animation: none;
        }
    }
    .pbar {
        height: 6px;
        border-radius: 999px;
        background: var(--mcat-track);
        overflow: hidden;
    }
    .pbar span {
        display: block;
        height: 100%;
        background: var(--accent);
        border-radius: 999px;
        transition: width 0.2s ease;
    }
    .qrow {
        display: flex;
        gap: 16px;
        align-items: flex-start;
    }
    .question {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 16px;
    }
    .qtext {
        font-size: 19px;
        font-weight: 600;
        line-height: 1.5;
    }
    .choices {
        display: flex;
        flex-direction: column;
        gap: 10px;
    }
    .choice {
        position: relative;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 16px;
        border: 1.5px solid var(--mcat-border);
        border-radius: 12px;
        cursor: pointer;
        font-size: 16px;
        transition:
            border-color 0.1s ease,
            background 0.1s ease;
    }
    .choice.selected {
        border-color: var(--accent);
        background: color-mix(in srgb, var(--accent) 8%, var(--mcat-surface));
    }
    .choice input {
        position: absolute;
        opacity: 0;
        pointer-events: none;
    }
    .ck {
        flex: 0 0 auto;
        width: 26px;
        height: 26px;
        border-radius: 7px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        font-size: 14px;
    }
    .choice.selected .ck {
        background: var(--accent);
        color: #fff;
        border-color: var(--accent);
    }
    .firstpick {
        margin-left: auto;
        font-size: 11px;
        font-weight: 700;
        color: var(--mcat-muted);
        background: var(--mcat-surface-2);
        border-radius: 999px;
        padding: 3px 9px;
    }
    .conf-label {
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-muted);
        display: block;
        margin-bottom: 8px;
    }
    .seg {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 8px;
    }
    .seg-btn {
        appearance: none;
        cursor: pointer;
        border: 1.5px solid var(--mcat-border);
        background: var(--mcat-surface);
        color: var(--mcat-text);
        border-radius: 10px;
        padding: 11px;
        font-size: 15px;
        font-weight: 700;
    }
    .seg-btn.on {
        border-color: var(--accent);
        color: var(--accent);
        background: color-mix(in srgb, var(--accent) 10%, var(--mcat-surface));
    }
    .second-hint {
        margin: 0;
        font-size: 15px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
    }
    .back-btn {
        margin-right: auto;
    }
    .side {
        flex: 0 0 190px;
        position: sticky;
        top: 64px;
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 14px;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 12px;
        box-shadow: var(--mcat-shadow);
    }
    .side-title {
        font-weight: 700;
        font-size: 13px;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mcat-muted);
    }
    .side-stat {
        display: flex;
        flex-direction: column;
        line-height: 1;
    }
    .side-num {
        font-size: 28px;
        font-weight: 800;
    }
    .side-stat.bad .side-num {
        color: var(--mcat-red);
    }
    .side-label {
        font-size: 12px;
        color: var(--mcat-muted);
        margin-top: 4px;
    }
    .side-note {
        font-size: 12px;
        color: var(--mcat-muted);
        margin: 0;
    }
    @media (max-width: 720px) {
        .qrow {
            flex-direction: column;
        }
        .side {
            flex-basis: auto;
            position: static;
            flex-direction: row;
            flex-wrap: wrap;
        }
    }
    .fb-title {
        font-weight: 800;
        font-size: 18px;
        margin-bottom: 6px;
    }
    .results {
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 14px;
        max-width: 680px;
        margin: 0 auto;
        width: 100%;
        /* Fill the viewport so results aren't stranded above a big blank area. */
        min-height: calc(100dvh - 170px);
    }
    .rv-intro {
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
        gap: 4px;
        padding: 4px 0 2px;
    }
    .rv-score {
        font-size: 24px;
        font-weight: 800;
        color: var(--mcat-text);
    }
    .rv-sub {
        font-size: 15px;
        color: var(--mcat-muted);
        max-width: 32ch;
    }
    .rv-grid-card {
        padding: 18px 18px 16px;
    }
    .rv-grid-title {
        font-size: 15px;
        font-weight: 800;
        margin-bottom: 14px;
    }
    .rv-grid {
        display: grid;
        grid-template-columns: repeat(5, 1fr);
        gap: 12px;
    }
    @media (max-width: 520px) {
        .rv-grid {
            grid-template-columns: repeat(4, 1fr);
        }
    }
    .tile {
        appearance: none;
        cursor: pointer;
        border: 1.5px solid transparent;
        border-radius: 16px;
        aspect-ratio: 1 / 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 6px;
        font-weight: 800;
        transition:
            transform 0.12s ease,
            box-shadow 0.12s ease;
    }
    .tile:hover {
        transform: translateY(-2px);
        box-shadow: var(--mcat-shadow);
    }
    .tile-num {
        font-size: 22px;
    }
    .tile-mark {
        width: 17px;
        height: 17px;
        border-radius: 5px;
        border: 2px solid currentColor;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        font-weight: 900;
        line-height: 1;
        opacity: 0.5;
    }
    .tile.seen .tile-mark {
        opacity: 1;
        background: color-mix(in srgb, currentColor 16%, transparent);
    }
    .tile.correct {
        color: var(--mcat-green);
        background: color-mix(in srgb, var(--mcat-green) 15%, var(--mcat-surface));
    }
    .tile.shaky {
        color: var(--mcat-amber);
        background: color-mix(in srgb, var(--mcat-amber) 18%, var(--mcat-surface));
    }
    .tile.missed {
        color: var(--mcat-red);
        background: color-mix(in srgb, var(--mcat-red) 14%, var(--mcat-surface));
    }
    .rv-legend {
        display: flex;
        flex-wrap: wrap;
        gap: 16px;
        justify-content: center;
        margin-top: 16px;
        font-size: 13px;
        font-weight: 700;
    }
    .lg {
        display: inline-flex;
        align-items: center;
        gap: 6px;
    }
    .lg i {
        width: 12px;
        height: 12px;
        border-radius: 4px;
        border: 2px solid currentColor;
    }
    .lg.correct {
        color: var(--mcat-green);
    }
    .lg.shaky {
        color: var(--mcat-amber);
    }
    .lg.missed {
        color: var(--mcat-red);
    }
    .rv-cta {
        display: flex;
        flex-direction: column;
        gap: 8px;
    }
    .rv-hint {
        margin: 2px 0 0;
        text-align: center;
        font-size: 13px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .rv-dots {
        display: flex;
        gap: 6px;
        justify-content: center;
        flex-wrap: wrap;
    }
    .dot-seg {
        appearance: none;
        cursor: pointer;
        border: none;
        width: 26px;
        height: 8px;
        border-radius: 999px;
        background: var(--mcat-track);
        opacity: 0.6;
        transition:
            opacity 0.12s ease,
            transform 0.12s ease;
    }
    .dot-seg.correct {
        background: var(--mcat-green);
    }
    .dot-seg.shaky {
        background: var(--mcat-amber);
    }
    .dot-seg.missed {
        background: var(--mcat-red);
    }
    .dot-seg.cur {
        opacity: 1;
        transform: scaleY(1.5);
    }
    .rv-card {
        display: flex;
        flex-direction: column;
        gap: 14px;
        padding: 20px 22px;
    }
    .rv-card-head {
        display: flex;
        align-items: center;
        gap: 10px;
    }
    .verdict-pill {
        font-size: 13px;
        font-weight: 800;
        border-radius: 999px;
        padding: 4px 12px;
    }
    .verdict-pill.correct {
        color: var(--mcat-green);
        background: color-mix(in srgb, var(--mcat-green) 14%, var(--mcat-surface));
    }
    .verdict-pill.shaky {
        color: var(--mcat-amber);
        background: color-mix(in srgb, var(--mcat-amber) 16%, var(--mcat-surface));
    }
    .verdict-pill.missed {
        color: var(--mcat-red);
        background: color-mix(in srgb, var(--mcat-red) 14%, var(--mcat-surface));
    }
    .rv-count {
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
    }
    .rv-card-head :global(.mascot) {
        margin-left: auto;
    }
    .rv-title {
        font-size: 21px;
        font-weight: 800;
        line-height: 1.3;
        color: var(--mcat-text);
    }
    .rv-q-toggle {
        align-self: center;
        appearance: none;
        border: none;
        background: none;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
        padding: 2px 4px;
    }
    .rv-svg {
        display: flex;
        justify-content: center;
        padding: 14px;
        background: var(--mcat-surface-2);
        border-radius: 16px;
        /* SVG uses currentColor for axes/labels so it reads on any theme. */
        color: var(--mcat-text);
    }
    .rv-svg :global(svg) {
        max-width: 100%;
        height: auto;
        max-height: 240px;
    }
    .rv-svg-loading {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        padding: 44px 18px;
        background: var(--mcat-surface-2);
        border-radius: 16px;
    }
    .gen-dots {
        display: inline-flex;
        gap: 7px;
    }
    .gen-dots span {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--mcat-accent);
        animation: genbounce 1s ease-in-out infinite;
    }
    .gen-dots span:nth-child(2) {
        animation-delay: 0.15s;
    }
    .gen-dots span:nth-child(3) {
        animation-delay: 0.3s;
    }
    @keyframes genbounce {
        0%,
        100% {
            transform: translateY(0);
            opacity: 0.4;
        }
        40% {
            transform: translateY(-7px);
            opacity: 1;
        }
    }
    .gen-text {
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-muted);
    }
    @media (prefers-reduced-motion: reduce) {
        .gen-dots span {
            animation: none;
        }
    }
    .rv-answer {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        justify-content: center;
    }
    .rp {
        font-size: 13px;
        font-weight: 600;
        border-radius: 999px;
        padding: 4px 12px;
        border: 1px solid var(--mcat-border);
        color: var(--mcat-muted);
    }
    .rp.answer {
        color: var(--mcat-accent);
        border-color: color-mix(in srgb, var(--mcat-accent) 35%, var(--mcat-border));
        font-weight: 700;
    }
    .rv-key {
        margin: 4px 0;
        font-size: 18px;
        line-height: 1.6;
        color: var(--mcat-text);
        text-align: center;
    }
    .rv-src {
        margin: 0;
        text-align: center;
        font-size: 11px;
        font-style: italic;
        color: var(--mcat-muted);
    }
    /* Full-page question takeover (from "Show question"). */
    .qtakeover {
        display: flex;
        flex-direction: column;
        gap: 16px;
        padding: 24px 26px;
    }
    .qt-label {
        font-size: 13px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mcat-muted);
    }
    .qt-stem {
        font-size: 21px;
        font-weight: 700;
        line-height: 1.55;
        color: var(--mcat-text);
    }
    .qt-choices {
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .qt-choice {
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 16px 18px;
        border: 1.5px solid var(--mcat-border);
        border-radius: 14px;
        font-size: 18px;
        line-height: 1.45;
        color: var(--mcat-text);
    }
    .qt-choice.correct {
        border-color: var(--mcat-green);
        background: color-mix(in srgb, var(--mcat-green) 12%, var(--mcat-surface));
    }
    .qt-ck {
        flex: 0 0 auto;
        width: 32px;
        height: 32px;
        border-radius: 9px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        font-size: 16px;
    }
    .qt-choice.correct .qt-ck {
        background: var(--mcat-green);
        color: #fff;
        border-color: var(--mcat-green);
    }
    .qt-back {
        align-self: flex-start;
        margin-top: 4px;
    }
    .rv-nav {
        display: flex;
        gap: 10px;
    }
    .pager-btn {
        flex: 1;
    }
    .pager-btn:disabled {
        opacity: 0.45;
        cursor: not-allowed;
    }
    .rv-back-all {
        align-self: center;
        appearance: none;
        border: none;
        background: none;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
    }
    .reasoning {
        display: flex;
        flex-direction: column;
        gap: 8px;
    }
    .reasoning-label {
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .reasoning-input {
        width: 100%;
        border: 1.5px solid var(--mcat-border);
        border-radius: 12px;
        padding: 12px 14px;
        background: var(--mcat-surface);
        color: var(--mcat-text);
        font: inherit;
        font-size: 15px;
        resize: vertical;
    }
    .reasoning-input:focus {
        outline: none;
        border-color: var(--accent);
    }
</style>
