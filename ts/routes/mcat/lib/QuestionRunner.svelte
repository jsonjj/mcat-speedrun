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

    import { postJson } from "./api";
    import { CONFIDENCE_LABELS, SECTION_NAMES } from "./types";
    import type { FirstPassResponse, QuestionBatch, RevealResult } from "./types";

    export let batch: QuestionBatch;
    export let phase = "daily";
    export let label = "Performance Set";
    export let accent = "var(--mcat-amber)";
    export let seconds = 90;

    const dispatch = createEventDispatcher<{ complete: { results: RevealResult[] } }>();

    type FirstAnswer = { choice: string; confidence: string; time_ms: number };
    type SecondAnswer = { choice: string; reasoning: string };

    let stage: "first" | "feedback" | "second" | "results" = "first";
    let idx = 0;
    const firstAnswers: Record<number, FirstAnswer> = {};
    const secondAnswers: Record<number, SecondAnswer> = {};
    let firstResp: FirstPassResponse | null = null;
    let results: RevealResult[] = [];
    let busy = false;

    let curChoice = "";
    let curConfidence = "";
    let questionStart = Date.now();

    // Per-item countdown.
    let timeLeft = seconds;
    let timerId: ReturnType<typeof setInterval> | undefined;
    onMount(() => {
        timerId = setInterval(() => {
            if (timeLeft > 0 && (stage === "first" || stage === "second")) {
                timeLeft -= 1;
            }
        }, 1000);
    });
    onDestroy(() => clearInterval(timerId));
    function resetTimer(): void {
        timeLeft = seconds;
    }
    $: mmss = `${Math.floor(timeLeft / 60)}:${String(timeLeft % 60).padStart(2, "0")}`;

    $: total = batch.questions.length;
    $: q = batch.questions[idx];
    $: progressPct = total ? (idx / total) * 100 : 0;

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
        firstAnswers[q.note_id] = {
            choice: curChoice,
            confidence: curConfidence,
            time_ms: Date.now() - questionStart,
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
        resetTimer();
    }

    async function nextSecond(): Promise<void> {
        if (!curChoice) {
            return;
        }
        secondAnswers[batch.questions[idx].note_id] = {
            choice: curChoice,
            reasoning: "",
        };
        if (idx + 1 < total) {
            idx += 1;
            curChoice = secondAnswers[batch.questions[idx].note_id]?.choice ?? "";
            resetTimer();
        } else {
            await submitSecond();
        }
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

    function labelText(label2: string | null | undefined): string {
        return label2 ? label2.replace(/_/g, " ") : "";
    }

    function firstPick(noteId: number): string {
        return firstAnswers[noteId]?.choice ?? "";
    }
</script>

<div class="runner" style={`--accent:${accent}`}>
    {#if stage === "first" || stage === "second"}
        <div class="rhead">
            <span class="rtag">
                <span class="dot"></span>
                {label} · {SECTION_NAMES[q.section] ?? q.section} · Item {idx + 1} Of {total}
            </span>
            <span class="timer" class:low={timeLeft <= 10}>{mmss}</span>
        </div>
        <div class="pbar"><span style={`width:${progressPct}%`}></span></div>

        <div class="qrow">
            <div class="mcat-card question">
                <div class="qtext">{q.question}</div>
                <div class="choices">
                    {#each q.choices as choice (choice.key)}
                        <label class="choice" class:selected={curChoice === choice.key}>
                            <input
                                type="radio"
                                name={`q-${q.note_id}-${stage}`}
                                value={choice.key}
                                bind:group={curChoice}
                            />
                            <span class="ck">{choice.key}</span>
                            <span class="ctext">{choice.text}</span>
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
                {:else}
                    <p class="second-hint">
                        Second pass — take another look and lock in your final answer.
                    </p>
                {/if}

                <div class="actions">
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={busy ||
                            !curChoice ||
                            (stage === "first" ? !curConfidence : false)}
                        on:click={stage === "first" ? nextFirst : nextSecond}
                    >
                        {idx + 1 < total ? "Submit & Next" : "Submit Response"}
                    </button>
                </div>
            </div>

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
    {:else}
        <div class="results">
            <div class="mcat-card rsummary">
                <div class="fb-title">Results</div>
                <p class="mcat-muted">
                    First-answer correct: {results.filter((r) => r.first_correct)
                        .length}/{results.length}
                </p>
            </div>
            {#each results as r (r.note_id)}
                <div class="mcat-card result" class:good={r.first_correct}>
                    <div class="result-q">{questionById(r.note_id)}</div>
                    <div class="result-line">
                        <span class="rp {r.first_correct ? 'g' : 'b'}">
                            first: {r.first_correct ? "correct" : "missed"}
                        </span>
                        {#if r.second_correct !== undefined}
                            <span class="rp {r.second_correct ? 'g' : 'b'}">
                                second: {r.second_correct ? "correct" : "missed"}
                            </span>
                        {/if}
                        <span class="rp">answer: {r.correct}</span>
                        {#if r.label}<span class="rp">{labelText(r.label)}</span>{/if}
                    </div>
                    {#if r.explanation}<p class="explanation">{r.explanation}</p>{/if}
                </div>
            {/each}
            <button
                class="mcat-btn mcat-btn-primary"
                on:click={() => dispatch("complete", { results })}
            >
                Done
            </button>
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
        gap: 12px;
    }
    .result-q {
        font-weight: 600;
        margin-bottom: 8px;
    }
    .result-line {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-bottom: 8px;
    }
    .rp {
        font-size: 12px;
        font-weight: 600;
        border-radius: 999px;
        padding: 3px 10px;
        border: 1px solid var(--mcat-border);
        color: var(--mcat-muted);
    }
    .rp.g {
        color: var(--mcat-green);
        border-color: color-mix(in srgb, var(--mcat-green) 35%, var(--mcat-border));
    }
    .rp.b {
        color: var(--mcat-red);
        border-color: color-mix(in srgb, var(--mcat-red) 35%, var(--mcat-border));
    }
    .explanation {
        margin: 0;
        font-size: 15px;
        color: var(--mcat-muted);
    }
</style>
