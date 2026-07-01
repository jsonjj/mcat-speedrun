<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";

    import { postJson } from "../lib/api";
    import QuestionRunner from "../lib/QuestionRunner.svelte";
    import { playStart } from "../lib/sound";
    import type { QuestionBatch } from "../lib/types";

    const options = [
        {
            kind: "quick",
            title: "Quick Diagnostic",
            detail: "~12 questions · 15–20 min",
            note: "Very wide range. Fastest start.",
        },
        {
            kind: "standard",
            title: "Standard Diagnostic",
            detail: "~20 questions · ~30 min",
            note: "Recommended balance of effort and accuracy.",
        },
        {
            kind: "best_estimate",
            title: "Best-Estimate Diagnostic",
            detail: "~40 questions · ~60 min",
            note: "Best personalization and the tightest estimated range.",
        },
    ];

    let batch: QuestionBatch | null = null;
    let kind = "";
    let loading = false;
    let done = false;

    async function start(selected: string): Promise<void> {
        kind = selected;
        loading = true;
        playStart("diagnostic");
        batch = await postJson<QuestionBatch>("mcatDiagnosticQuestions", {
            kind: selected,
        });
        loading = false;
    }

    async function finish(): Promise<void> {
        await postJson("mcatCompleteDiagnostic", { kind });
        done = true;
    }
</script>

<div class="mcat-container">
    <header class="mcat-header">
        <div>
            <h1 class="mcat-title">Diagnostic Placement</h1>
            <p class="mcat-subtitle">Start from where you are, not square one.</p>
        </div>
    </header>

    {#if !batch && !done}
        <p class="lead mcat-muted">Longer = a tighter estimate. You can start short.</p>
        <section class="mcat-grid">
            {#each options as opt (opt.kind)}
                <button class="mcat-card opt" on:click={() => start(opt.kind)}>
                    <div class="opt-title">{opt.title}</div>
                    <div class="opt-detail mcat-muted">{opt.detail}</div>
                    <div class="opt-note">{opt.note}</div>
                </button>
            {/each}
        </section>
    {:else if loading}
        <div class="mcat-card">Building your diagnostic…</div>
    {:else if done}
        <div class="mcat-card finished">
            <h2>Diagnostic complete</h2>
            <p class="mcat-muted">
                Your plan's ready. Thin areas stay uncertain for now.
            </p>
            <button
                class="mcat-btn mcat-btn-primary"
                on:click={() => goto("/mcat/dashboard")}
            >
                See your starting estimate
            </button>
        </div>
    {:else if batch && batch.questions.length > 0}
        {#key batch.batch_id}
            <QuestionRunner
                {batch}
                phase="diagnostic"
                label="Diagnostic"
                accent="var(--mcat-blue)"
                on:complete={finish}
            />
        {/key}
    {:else}
        <div class="mcat-card">
            <p>
                No questions available. Install starter content from the dashboard
                first.
            </p>
            <button class="mcat-btn" on:click={() => goto("/mcat/dashboard")}>
                Go to dashboard
            </button>
        </div>
    {/if}
</div>

<style lang="scss">
    .lead {
        max-width: 640px;
        margin: 0 0 20px;
        font-size: 14px;
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
        font-size: 16px;
    }
    .opt-detail {
        font-size: 13px;
    }
    .opt-note {
        font-size: 13px;
    }
    .finished h2 {
        margin-top: 0;
    }
</style>
