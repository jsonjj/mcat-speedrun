<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

CARS as a debate with the author, not a worksheet: challenge the argument,
switch sides and defend it, then test it against a new condition. No AI grading
yet, so after you commit your reasoning we reveal model answers (a strong
rebuttal and a strong defense) to self-compare against, plus a quick rubric you
rate yourself on. Responses + self-rating are stored (AI-ready) for later.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { playStart } from "../lib/sound";
    import type { CarsPassage, CarsResponse } from "../lib/types";

    let passage: CarsPassage | null = null;
    let rubric: string[] = [];
    let rubricChecks: boolean[] = [];
    let loading = true;
    let responses: Record<number, string> = {};
    let verdict = "";
    let revealed = false;
    let saving = false;
    let blockId: string | null = null;
    let fromRoadmap = false;

    const verdicts = [
        { key: "stronger", label: "Stronger" },
        { key: "weaker", label: "Weaker" },
        { key: "unchanged", label: "Unchanged" },
    ];

    async function load(): Promise<void> {
        loading = true;
        responses = {};
        verdict = "";
        revealed = false;
        const resp = await postJson<CarsResponse>("mcatCars");
        passage = resp.passage;
        rubric = resp.rubric ?? [];
        rubricChecks = rubric.map(() => false);
        loading = false;
    }

    $: lastPromptIsVerdict =
        passage !== null &&
        passage.prompts.length > 0 &&
        /stronger|weaker|unchanged/i.test(passage.prompts[passage.prompts.length - 1]);

    $: allPrompts = passage ? passage.prompts : [];
    $: textPrompts = lastPromptIsVerdict ? allPrompts.slice(0, -1) : allPrompts;
    $: verdictPrompt =
        lastPromptIsVerdict && allPrompts.length > 0
            ? allPrompts[allPrompts.length - 1]
            : "";

    function skillFor(i: number): string {
        return passage?.prompt_skills?.[i] ?? "";
    }

    $: canReveal =
        textPrompts.every((_p, i) => (responses[i] ?? "").trim().length > 0) &&
        (!lastPromptIsVerdict || verdict !== "");

    function reveal(): void {
        if (canReveal) {
            revealed = true;
        }
    }

    async function finish(after: () => void): Promise<void> {
        if (!passage) {
            return;
        }
        saving = true;
        try {
            const missTypes = rubric.filter((_r, i) => !rubricChecks[i]);
            await postJson("mcatSubmitCars", {
                note_id: passage.note_id,
                responses,
                verdict: verdict || null,
                miss_types: missTypes,
            });
            if (fromRoadmap && blockId) {
                await postJson("mcatCompleteBlock", { block_id: blockId });
            }
            after();
        } finally {
            saving = false;
        }
    }

    onMount(() => {
        blockId = $page.url.searchParams.get("block");
        fromRoadmap = $page.url.searchParams.get("from") === "roadmap";
        load();
        playStart("cars");
    });
</script>

<div class="mcat-container">
    <header class="mcat-header">
        <div>
            <h1 class="mcat-title">CARS Author Duel</h1>
            <p class="mcat-subtitle">
                Debate the author. Challenge it, defend it, then stress-test it.
            </p>
        </div>
    </header>

    {#if loading}
        <div class="mcat-card">Loading a passage…</div>
    {:else if !passage}
        <div class="mcat-card">
            <p>
                No CARS passage available yet. Install starter content from the
                dashboard.
            </p>
            <button class="mcat-btn" on:click={() => goto("/mcat/dashboard")}>
                Go to dashboard
            </button>
        </div>
    {:else}
        <div class="mcat-card passage">
            <div class="passage-label mcat-muted">Passage</div>
            <p class="passage-text">{passage.passage}</p>
        </div>

        {#if !revealed}
            <div class="prompts">
                {#each textPrompts as prompt, i (i)}
                    <div class="mcat-card prompt">
                        <div class="prompt-head">
                            <label class="prompt-q" for={`prompt-${i}`}>{prompt}</label>
                            {#if skillFor(i)}<span class="skill-chip">
                                    {skillFor(i)}
                                </span>{/if}
                        </div>
                        <textarea
                            id={`prompt-${i}`}
                            rows="3"
                            bind:value={responses[i]}
                        ></textarea>
                    </div>
                {/each}

                {#if lastPromptIsVerdict}
                    <div class="mcat-card prompt">
                        <div class="prompt-head">
                            <div class="prompt-q">{verdictPrompt}</div>
                            {#if skillFor(textPrompts.length)}<span class="skill-chip">
                                    {skillFor(textPrompts.length)}
                                </span>{/if}
                        </div>
                        <div class="verdicts">
                            {#each verdicts as v (v.key)}
                                <button
                                    type="button"
                                    class="mcat-btn"
                                    class:selected={verdict === v.key}
                                    on:click={() => (verdict = v.key)}
                                >
                                    {v.label}
                                </button>
                            {/each}
                        </div>
                    </div>
                {/if}

                <button
                    class="mcat-btn mcat-btn-primary"
                    disabled={!canReveal}
                    on:click={reveal}
                >
                    Commit & compare answers
                </button>
            </div>
        {:else}
            <div class="mcat-card reveal">
                <div class="feedback-title">The author's core claim</div>
                <p>{passage.author_claim}</p>
                <p class="mcat-muted skill">
                    CARS skill: {passage.skill_type.replace(/_/g, " ")}
                </p>

                {#if passage.strong_rebuttal || passage.strong_defense}
                    <div class="models">
                        {#if passage.strong_rebuttal}
                            <div class="model">
                                <div class="model-title">A strong challenge</div>
                                <p>{passage.strong_rebuttal}</p>
                            </div>
                        {/if}
                        {#if passage.strong_defense}
                            <div class="model">
                                <div class="model-title">A strong defense</div>
                                <p>{passage.strong_defense}</p>
                            </div>
                        {/if}
                    </div>
                {/if}
            </div>

            {#if rubric.length}
                <div class="mcat-card rubric">
                    <div class="feedback-title">Rate your reasoning</div>
                    <p class="mcat-muted">
                        Check what you actually did — the rest is logged as a focus
                        area.
                    </p>
                    {#each rubric as item, i (i)}
                        <label class="rubric-item">
                            <input type="checkbox" bind:checked={rubricChecks[i]} />
                            <span>{item}</span>
                        </label>
                    {/each}
                </div>
            {/if}

            <div class="row">
                {#if fromRoadmap}
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={saving}
                        on:click={() => finish(() => goto("/mcat/roadmap"))}
                    >
                        {saving ? "Saving…" : "Save & back to roadmap"}
                    </button>
                {:else}
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={saving}
                        on:click={() => finish(() => goto("/mcat/dashboard"))}
                    >
                        {saving ? "Saving…" : "Save & finish"}
                    </button>
                    <button
                        class="mcat-btn"
                        disabled={saving}
                        on:click={() => finish(load)}
                    >
                        Save & another passage
                    </button>
                {/if}
            </div>
        {/if}
    {/if}
</div>

<style lang="scss">
    .passage {
        margin-bottom: 18px;
    }
    .passage-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin-bottom: 8px;
    }
    .passage-text {
        margin: 0;
        font-size: 18px;
        line-height: 1.6;
    }
    .prompts {
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .prompt-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 8px;
    }
    .prompt-q {
        font-weight: 600;
    }
    .skill-chip {
        flex: 0 0 auto;
        font-size: 12px;
        font-weight: 600;
        color: var(--mcat-accent);
        background: color-mix(in srgb, var(--mcat-accent) 12%, transparent);
        border: 1px solid color-mix(in srgb, var(--mcat-accent) 30%, transparent);
        border-radius: 999px;
        padding: 3px 10px;
        white-space: nowrap;
    }
    textarea {
        width: 100%;
        border-radius: 10px;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-bg);
        color: var(--mcat-text);
        padding: 10px 12px;
        font: inherit;
        font-size: 15px;
        resize: vertical;
    }
    .verdicts {
        display: flex;
        gap: 8px;
    }
    .selected {
        border-color: var(--mcat-accent);
        color: var(--mcat-accent);
    }
    .feedback-title {
        font-weight: 700;
        font-size: 18px;
        margin-bottom: 6px;
    }
    .skill {
        font-size: 13px;
    }
    .models {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 14px;
        margin-top: 14px;
    }
    @media (max-width: 720px) {
        .models {
            grid-template-columns: 1fr;
        }
    }
    .model {
        background: var(--mcat-bg);
        border: 1px solid var(--mcat-border);
        border-radius: 12px;
        padding: 14px 16px;
    }
    .model-title {
        font-weight: 700;
        font-size: 14px;
        margin-bottom: 6px;
        color: var(--mcat-accent);
    }
    .model p {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
    }
    .rubric {
        margin-top: 16px;
        display: flex;
        flex-direction: column;
        gap: 4px;
    }
    .rubric-item {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 8px 0;
        font-size: 15px;
        cursor: pointer;
    }
    .rubric-item input {
        margin-top: 3px;
        width: 17px;
        height: 17px;
        flex: 0 0 auto;
    }
    .row {
        display: flex;
        gap: 10px;
        margin-top: 16px;
        flex-wrap: wrap;
    }
</style>
