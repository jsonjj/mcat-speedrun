<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Mini-MCAT / section problem set. Like the diagnostic, you choose how many
questions before starting. Reached from Extra Practice (after the daily roadmap
is done) or from a roadmap block.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import QuestionRunner from "../lib/QuestionRunner.svelte";
    import { playStart } from "../lib/sound";
    import { SECTION_NAMES } from "../lib/types";
    import type { Profile, QuestionBatch } from "../lib/types";

    // ~1.5 min per question is a reasonable MCAT-form pace estimate.
    const MIN_PER_Q = 1.5;

    let batch: QuestionBatch | null = null;
    let loading = false;
    let started = false;
    let done = false;
    let section: string | null = null;
    let blockId: string | null = null;
    let fromRoadmap = false;
    let aiEnabled = false;

    // All-sections Mini-MCAT counts divide evenly across the four sections.
    const MINI_OPTIONS = [8, 12, 20];
    const SECTION_OPTIONS = [5, 10, 15];

    $: options = section ? SECTION_OPTIONS : MINI_OPTIONS;

    function estMin(n: number): number {
        return Math.round(n * MIN_PER_Q);
    }

    async function start(n: number): Promise<void> {
        started = true;
        loading = true;
        done = false;
        if (section) {
            batch = await postJson<QuestionBatch>("mcatQuestions", {
                section,
                count: n,
            });
        } else {
            batch = await postJson<QuestionBatch>("mcatMiniQuestions", { count: n });
        }
        loading = false;
    }

    // Finishing a roadmap task marks its block done and returns to the roadmap;
    // otherwise (Extra Practice) we show the normal done screen.
    async function onComplete(): Promise<void> {
        if (fromRoadmap && blockId) {
            await postJson("mcatCompleteBlock", { block_id: blockId });
            goto("/mcat/roadmap");
        } else {
            done = true;
        }
    }

    function restart(): void {
        batch = null;
        started = false;
        done = false;
    }

    onMount(async () => {
        section = $page.url.searchParams.get("section");
        blockId = $page.url.searchParams.get("block");
        fromRoadmap = $page.url.searchParams.get("from") === "roadmap";
        playStart("performance");
        try {
            const p = await postJson<{ profile: Profile }>("mcatGetProfile");
            aiEnabled = p.profile.ai_enabled ?? false;
        } catch {
            aiEnabled = false;
        }
        // Roadmap tasks are prescribed, so skip the chooser and start right away.
        if (fromRoadmap) {
            const c = Number($page.url.searchParams.get("count"));
            const fallback = section ? 10 : 12;
            start(c > 0 ? c : fallback);
        }
    });
</script>

<div class="mcat-container">
    <header class="mcat-header">
        <div>
            <h1 class="mcat-title">
                {section
                    ? `${SECTION_NAMES[section] ?? section} Practice`
                    : "Mini-MCAT"}
            </h1>
            <p class="mcat-subtitle">
                {section
                    ? "Focused problem set with confidence and second-pass reasoning."
                    : "Real exam form across all four sections."}
            </p>
        </div>
    </header>

    {#if !started}
        <p class="lead mcat-muted">Pick how many questions to do.</p>
        <section class="mcat-grid">
            {#each options as n (n)}
                <button class="mcat-card opt" on:click={() => start(n)}>
                    <div class="opt-title">{n} questions</div>
                    <div class="opt-detail mcat-muted">~{estMin(n)} min</div>
                </button>
            {/each}
        </section>
    {:else if loading}
        <div class="mcat-card">Building your set…</div>
    {:else if !batch || batch.questions.length === 0}
        <div class="mcat-card">
            <p>
                No questions available yet. Install starter content from the dashboard.
            </p>
            <button class="mcat-btn" on:click={() => goto("/mcat/dashboard")}>
                Go to dashboard
            </button>
        </div>
    {:else if done}
        <div class="mcat-card finished">
            <h2>Nice work</h2>
            <p class="mcat-muted">Saved — your scores are updated.</p>
            <div class="row">
                <button
                    class="mcat-btn mcat-btn-primary"
                    on:click={() => goto("/mcat/dashboard")}
                >
                    See updated scores
                </button>
                <button class="mcat-btn" on:click={restart}>Another set</button>
            </div>
        </div>
    {:else}
        {#key batch.batch_id}
            <QuestionRunner
                {batch}
                {aiEnabled}
                phase="daily"
                label={section ? "Section Practice" : "Mini-MCAT"}
                accent="var(--mcat-blue)"
                on:complete={onComplete}
            />
        {/key}
    {/if}
</div>

<style lang="scss">
    .lead {
        max-width: 620px;
        margin: 0 0 20px;
        font-size: 16px;
    }
    .opt {
        text-align: left;
        cursor: pointer;
        display: flex;
        flex-direction: column;
        gap: 6px;
    }
    .opt-title {
        font-weight: 700;
        font-size: 19px;
    }
    .opt-detail {
        font-size: 15px;
    }
    .finished h2 {
        margin-top: 0;
    }
    .row {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
    }
</style>
