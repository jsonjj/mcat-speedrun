<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Detail page for a single score (Memory / Performance / Readiness). Reached by
tapping a score tile on the dashboard or account page. Explains the number and
the evidence behind it, in short lines, with a Back button.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { evidence, toneVar } from "../lib/blocks";
    import type { DashboardData, ScoreBlock } from "../lib/types";

    type ScoreId = "memory" | "performance" | "readiness";

    const META: Record<ScoreId, { title: string; means: string; how: string }> = {
        memory: {
            title: "Memory Recall",
            means: "Can you recall prerequisites right now?",
            how: "Graded recall on your memory cards (FSRS).",
        },
        performance: {
            title: "Applied Under Exam Conditions",
            means: "Can you apply it to new questions?",
            how: "First-answer accuracy on fresh questions.",
        },
        readiness: {
            title: "Overall Readiness",
            means: "Your likely MCAT range today.",
            how: "Blends coverage, performance and calibration.",
        },
    };

    let data: DashboardData | null = null;
    let loading = true;

    $: id = ($page.url.searchParams.get("id") ?? "readiness") as ScoreId;
    $: meta = META[id] ?? META.readiness;
    $: block = data?.scores ? data.scores[id] : null;
    $: ev = block ? evidence(block) : null;
    $: color = ev ? toneVar(ev.tone) : "var(--mcat-accent)";
    $: heroText = ev && ev.tone === "amber" ? "#1f2a3a" : "#ffffff";

    function isPercent(b: ScoreBlock): boolean {
        return b.unit === "percent_recall" || b.unit === "percent_correct";
    }

    function big(b: ScoreBlock): string {
        if (b.abstained) {
            return "—";
        }
        if (b.low !== null && b.high !== null) {
            return isPercent(b)
                ? `${Math.round(b.low)} – ${Math.round(b.high)}%`
                : `${Math.round(b.low)} – ${Math.round(b.high)}`;
        }
        if (b.point !== null) {
            return isPercent(b) ? `${Math.round(b.point)}%` : `${Math.round(b.point)}`;
        }
        return "—";
    }

    function scaleMax(b: ScoreBlock): string {
        if (b.abstained) {
            return "";
        }
        if (b.unit === "mcat_total") {
            return "/ 528";
        }
        if (b.unit === "section_score") {
            return "/ 132";
        }
        return "";
    }

    function back(): void {
        if (history.length > 1) {
            history.back();
        } else {
            goto("/mcat/dashboard");
        }
    }

    async function load(): Promise<void> {
        loading = true;
        data = await postJson<DashboardData>("mcatDashboard");
        loading = false;
    }

    onMount(load);
</script>

<div class="mcat-container narrow">
    <button class="back" on:click={back}>← Back</button>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if !block}
        <div class="mcat-card mcat-muted">
            No score yet. Install content and do some practice first.
        </div>
    {:else}
        <div class="hero" style={`--c:${color};--t:${heroText}`}>
            <div class="hero-title">{meta.title}</div>
            <div class="hero-big">
                {big(block)}{#if scaleMax(block)}<span class="hero-suffix">
                        {scaleMax(block)}
                    </span>{/if}
            </div>
            <div class="hero-word">
                {block.abstained ? "Not enough evidence yet" : (ev?.label ?? "")}
            </div>
        </div>

        <p class="means">{meta.means}</p>

        <dl class="facts mcat-card">
            <div>
                <dt>How we get it</dt>
                <dd>{meta.how}</dd>
            </div>
            <div>
                <dt>Coverage</dt>
                <dd>{Math.round(block.coverage_pct * 100)}%</dd>
            </div>
            {#if block.point !== null && !block.abstained}
                <div>
                    <dt>Point estimate</dt>
                    <dd>
                        {isPercent(block)
                            ? `${Math.round(block.point)}%`
                            : Math.round(block.point)}
                    </dd>
                </div>
            {/if}
            <div>
                <dt>Evidence</dt>
                <dd>{block.abstained ? block.abstention_reason : block.evidence}</dd>
            </div>
            {#if block.missing}
                <div>
                    <dt>Missing</dt>
                    <dd>{block.missing}</dd>
                </div>
            {/if}
            <div>
                <dt>Best next</dt>
                <dd class="next">{block.best_next_action}</dd>
            </div>
        </dl>
    {/if}
</div>

<style lang="scss">
    .narrow {
        max-width: 760px;
    }
    .back {
        appearance: none;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-surface);
        color: var(--mcat-text);
        border-radius: 9px;
        padding: 8px 14px;
        font-size: 15px;
        font-weight: 600;
        cursor: pointer;
        margin-bottom: 16px;
    }
    .back:hover {
        background: var(--mcat-bg);
    }
    .hero {
        background: linear-gradient(
            158deg,
            color-mix(in srgb, var(--c), white 12%),
            var(--c) 46%,
            color-mix(in srgb, var(--c), black 16%)
        );
        color: var(--t);
        border-radius: 20px;
        padding: 24px 26px;
        box-shadow:
            inset 0 1px 0 rgba(255, 255, 255, 0.16),
            0 16px 32px -14px color-mix(in srgb, var(--c) 65%, transparent);
        margin-bottom: 18px;
    }
    .hero-title {
        font-size: 17px;
        font-weight: 700;
        opacity: 0.95;
        letter-spacing: -0.01em;
    }
    .hero-big {
        font-size: 58px;
        font-weight: 800;
        letter-spacing: -0.03em;
        line-height: 1.05;
        margin: 4px 0 2px;
        font-variant-numeric: tabular-nums;
    }
    .hero-suffix {
        font-size: 22px;
        font-weight: 600;
        letter-spacing: 0;
        opacity: 0.72;
        margin-left: 8px;
    }
    .hero-word {
        font-size: 15px;
        font-weight: 600;
        text-transform: capitalize;
        opacity: 0.9;
    }
    .means {
        font-size: 17px;
        font-weight: 600;
        margin: 0 0 16px;
    }
    .facts {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .facts div {
        display: grid;
        grid-template-columns: 120px 1fr;
        gap: 12px;
        align-items: baseline;
    }
    dt {
        color: var(--mcat-muted);
        font-weight: 600;
        font-size: 14.5px;
    }
    dd {
        margin: 0;
        font-size: 16px;
    }
    .next {
        font-weight: 700;
    }
</style>
