<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Score detail (Memory / Applied / Readiness). Reached by tapping a score on the
Scores dashboard. Each page ends in ONE contextual action ("Do this next") that
launches the exact targeted practice — so every option ladders up to a score.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { SECTION_WORD, evidence, toneVar } from "../lib/blocks";
    import Sparkline from "../lib/Sparkline.svelte";
    import type { AccountData } from "../lib/types";

    type ScoreId = "memory" | "performance" | "readiness";
    const SECTION_ORDER = ["bb", "cp", "ps", "cars"];
    const REVIEWS_GATE = 100;

    let data: AccountData | null = null;
    let loading = true;

    async function load(): Promise<void> {
        loading = true;
        data = await postJson<AccountData>("mcatAccount");
        loading = false;
    }
    onMount(load);

    $: id = ($page.url.searchParams.get("id") ?? "readiness") as ScoreId;
    $: scores = data?.scores ?? null;
    $: stats = data?.stats ?? null;
    $: trend = data?.trend ?? null;
    $: measure = id === "memory" ? "memory" : "performance";
    $: block = scores ? scores[id] : null;
    $: tone = block ? evidence(block).tone : "red";
    $: color = toneVar(tone);

    // Per-section rows for the measure (skip sections with no estimate).
    $: sectionRows = scores
        ? SECTION_ORDER.map((code) => {
              const s = scores.sections[code];
              const b = s
                  ? measure === "memory"
                      ? s.memory
                      : s.performance
                  : undefined;
              return {
                  code,
                  name: SECTION_WORD[code] ?? code,
                  point: b && !b.abstained && b.point != null ? b.point : null,
              };
          }).filter((r) => r.point != null)
        : [];
    $: weakest =
        sectionRows.length > 0
            ? [...sectionRows].sort((a, b) => (a.point ?? 0) - (b.point ?? 0))[0]
            : null;
    $: best =
        sectionRows.length > 0
            ? [...sectionRows].sort((a, b) => (b.point ?? 0) - (a.point ?? 0))[0]
            : null;

    $: series = trend ? (id === "memory" ? trend.recall : trend.applied) : [];
    $: thisWeek = stats
        ? id === "memory"
            ? stats.reps_this_week
            : stats.attempts_this_week
        : 0;
    $: reviews = stats?.reps ?? 0;
    $: toUnlock = Math.max(0, REVIEWS_GATE - reviews);
    $: unlockPct = Math.min(100, (reviews / REVIEWS_GATE) * 100);

    const TITLE: Record<ScoreId, string> = {
        memory: "Memory Recall",
        performance: "Applied Under Exam Conditions",
        readiness: "Overall Readiness",
    };

    function pctText(v: number | null | undefined): string {
        return v == null ? "—" : `${Math.round(v)}%`;
    }

    // The single contextual action.
    $: doNext =
        id === "memory"
            ? {
                  eyebrow: "Do this next",
                  title: weakest ? `${weakest.name} flashcards` : "A memory block",
                  sub: weakest ? "Your weakest section · 10 min" : "10 min",
                  href: weakest
                      ? `/mcat/flashcards?section=${weakest.code}`
                      : "/mcat/flashcards",
              }
            : {
                  eyebrow: "Keep the momentum",
                  title: weakest ? `Timed set — ${weakest.name}` : "A question set",
                  sub: weakest ? "Most to gain · 15 min" : "15 min",
                  href: weakest ? `/mcat/mini?section=${weakest.code}` : "/mcat/mini",
              };

    function back(): void {
        if (history.length > 1) {
            history.back();
        } else {
            goto("/mcat/dashboard");
        }
    }
</script>

<div class="mcat-container narrow">
    <button class="back" on:click={back}>← Back</button>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if !block}
        <div class="mcat-card mcat-muted">
            No score yet. Install content and do some practice first.
        </div>
    {:else if id === "readiness"}
        <!-- Readiness -->
        {#if block.abstained}
            <div class="hero red" style={`--c:${color}`}>
                <div class="hero-head">
                    <span class="hero-title">{TITLE.readiness}</span>
                    <span class="chip">Abstaining</span>
                </div>
                <p class="hero-msg">
                    Not enough evidence yet to give you an honest number.
                </p>
                <div class="unlock-nums">
                    <span>{reviews} of {REVIEWS_GATE} reviews</span>
                    <span>{toUnlock} to unlock</span>
                </div>
                <div class="unlock-track">
                    <div class="unlock-fill" style={`width:${unlockPct}%`}></div>
                </div>
            </div>

            <div class="mcat-card block">
                <div class="eyebrow">Why it's blank</div>
                <ul class="bullets">
                    <li>
                        Readiness combines recall and applied — it needs enough of both
                        to be trustworthy.
                    </li>
                    <li>We'd rather show nothing than a number you can't rely on.</li>
                </ul>
            </div>

            <div class="mcat-card block">
                <div class="eyebrow">Unlocks at {REVIEWS_GATE}</div>
                <ul class="bullets check">
                    <li>A calibrated 472–528 estimate</li>
                    <li>Per-section score ranges</li>
                </ul>
            </div>

            <button class="cta" on:click={() => goto("/mcat/flashcards")}>
                <div class="cta-eyebrow">Closest to unlocking</div>
                <div class="cta-title">Do a review set</div>
                <div class="cta-sub">Each set ≈ 8 reviews · 15 min</div>
            </button>
        {:else}
            <div class="hero" style={`--c:${color}`}>
                <div class="hero-head">
                    <span class="hero-title">{TITLE.readiness}</span>
                    <span class="chip">{evidence(block).label}</span>
                </div>
                <div class="hero-big">
                    {block.low != null && block.high != null
                        ? `${Math.round(block.low)} – ${Math.round(block.high)}`
                        : Math.round(block.point ?? 0)}
                    <span class="hero-suffix">/ 528</span>
                </div>
            </div>
            <button class="link-card" on:click={() => goto("/mcat/breakdown")}>
                See full breakdown →
            </button>
            <button class="cta" on:click={() => goto(doNext.href)}>
                <div class="cta-eyebrow">Sharpen the weakest area</div>
                <div class="cta-title">{doNext.title}</div>
                <div class="cta-sub">{doNext.sub}</div>
            </button>
        {/if}
    {:else}
        <!-- Memory / Applied -->
        <div class="hero" style={`--c:${color}`}>
            <div class="hero-head">
                <span class="hero-title">{TITLE[id]}</span>
                <span class="chip">{evidence(block).label}</span>
            </div>
            <div class="hero-row">
                <span class="hero-big">{pctText(block.point)}</span>
                {#if thisWeek > 0}
                    <span class="week-chip">{thisWeek} this week</span>
                {/if}
            </div>
            {#if series.length > 1}
                <div class="spark-wrap">
                    <Sparkline points={series} {color} />
                    <div class="spark-axis">
                        <span>4 wks ago</span>
                        <span>now</span>
                    </div>
                </div>
            {/if}
        </div>

        <div class="tiles">
            <div class="tile">
                <div class="tile-lab">
                    {id === "memory" ? "Reps logged" : "Sets logged"}
                </div>
                <div class="tile-val">
                    {id === "memory" ? (stats?.reps ?? 0) : (stats?.sets ?? 0)}
                </div>
            </div>
            <div class="tile">
                <div class="tile-lab">
                    {id === "memory" ? "Best section" : "First-try accuracy"}
                </div>
                <div class="tile-val small">
                    {#if id === "memory"}
                        {best ? best.name : "—"}
                    {:else}
                        {pctText(scores?.performance.point)}
                    {/if}
                </div>
            </div>
        </div>

        <div class="mcat-card block">
            <div class="eyebrow">By section</div>
            {#if sectionRows.length > 0}
                <div class="sec-rows">
                    {#each sectionRows as r (r.code)}
                        <div class="sec-row">
                            <span class="sec-name">{r.name}</span>
                            <div class="sec-track">
                                <div
                                    class="sec-fill"
                                    style={`width:${r.point}%;background:${toneVar(
                                        (r.point ?? 0) >= 70
                                            ? "green"
                                            : (r.point ?? 0) >= 45
                                              ? "amber"
                                              : "red",
                                    )}`}
                                ></div>
                            </div>
                            <span class="sec-pct">{pctText(r.point)}</span>
                        </div>
                    {/each}
                </div>
            {:else}
                <p class="mcat-muted">
                    No section data yet — do a set to fill this in.
                </p>
            {/if}
        </div>

        <button class="cta" on:click={() => goto(doNext.href)}>
            <div class="cta-eyebrow">{doNext.eyebrow}</div>
            <div class="cta-title">{doNext.title}</div>
            <div class="cta-sub">{doNext.sub}</div>
        </button>
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
    /* Soft tinted hero (matches the score card color). */
    .hero {
        background: color-mix(in srgb, var(--c) 12%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--c) 26%, var(--mcat-border));
        border-radius: 20px;
        padding: 22px 24px;
        margin-bottom: 14px;
    }
    .hero-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 10px;
    }
    .hero-title {
        font-size: 18px;
        font-weight: 800;
        color: var(--mcat-text);
    }
    .chip {
        font-size: 12.5px;
        font-weight: 800;
        color: var(--c);
        background: color-mix(in srgb, var(--c) 18%, transparent);
        padding: 4px 11px;
        border-radius: 999px;
        white-space: nowrap;
    }
    .hero-row {
        display: flex;
        align-items: center;
        gap: 14px;
    }
    .hero-big {
        font-size: 52px;
        font-weight: 800;
        letter-spacing: -0.03em;
        line-height: 1;
        color: var(--c);
        font-variant-numeric: tabular-nums;
    }
    .hero-suffix {
        font-size: 22px;
        font-weight: 600;
        opacity: 0.6;
        margin-left: 6px;
    }
    .week-chip {
        font-size: 13px;
        font-weight: 800;
        color: var(--c);
        background: color-mix(in srgb, var(--c) 16%, transparent);
        padding: 4px 11px;
        border-radius: 999px;
    }
    .spark-wrap {
        margin-top: 14px;
    }
    .spark-axis {
        display: flex;
        justify-content: space-between;
        margin-top: 4px;
        font-size: 11px;
        font-weight: 700;
        color: var(--c);
        opacity: 0.8;
    }
    /* Readiness abstain */
    .hero-msg {
        font-size: 16px;
        font-weight: 700;
        color: var(--c);
        margin: 0 0 16px;
    }
    .unlock-nums {
        display: flex;
        justify-content: space-between;
        font-size: 13px;
        font-weight: 800;
        color: var(--c);
        margin-bottom: 8px;
    }
    .unlock-track {
        height: 12px;
        border-radius: 999px;
        background: color-mix(in srgb, var(--c) 12%, var(--mcat-surface));
        overflow: hidden;
    }
    .unlock-fill {
        height: 100%;
        border-radius: 999px;
        background: var(--c);
        animation: grow 0.7s cubic-bezier(0.2, 0.8, 0.3, 1);
    }
    @keyframes grow {
        from {
            width: 0 !important;
        }
    }
    /* Tiles */
    .tiles {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
        margin-bottom: 14px;
    }
    .tile {
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 16px;
        padding: 16px 18px;
    }
    .tile-lab {
        font-size: 13px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .tile-val {
        font-size: 30px;
        font-weight: 800;
        letter-spacing: -0.02em;
        margin-top: 4px;
        font-variant-numeric: tabular-nums;
    }
    .tile-val.small {
        font-size: 22px;
        color: var(--mcat-green);
    }
    /* Blocks */
    .block {
        margin-bottom: 14px;
    }
    .eyebrow {
        font-size: 11.5px;
        font-weight: 800;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--mcat-muted);
        margin-bottom: 12px;
    }
    .bullets {
        margin: 0;
        padding: 0;
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .bullets li {
        position: relative;
        padding-left: 26px;
        font-size: 15px;
        font-weight: 500;
        line-height: 1.4;
    }
    .bullets li::before {
        content: "";
        position: absolute;
        left: 0;
        top: 4px;
        width: 14px;
        height: 14px;
        border-radius: 4px;
        border: 2px solid var(--mcat-accent);
    }
    .bullets.check li::before {
        background: color-mix(in srgb, var(--mcat-green) 20%, transparent);
        border-color: var(--mcat-green);
    }
    /* By-section bars */
    .sec-rows {
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .sec-row {
        display: grid;
        grid-template-columns: 110px 1fr 44px;
        align-items: center;
        gap: 12px;
    }
    .sec-name {
        font-size: 15px;
        font-weight: 700;
    }
    .sec-track {
        height: 10px;
        border-radius: 999px;
        background: var(--mcat-track);
        overflow: hidden;
    }
    .sec-fill {
        height: 100%;
        border-radius: 999px;
    }
    .sec-pct {
        font-size: 14px;
        font-weight: 800;
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    /* The single contextual CTA */
    .cta {
        display: block;
        width: 100%;
        text-align: left;
        appearance: none;
        cursor: pointer;
        border: 1.5px solid
            color-mix(in srgb, var(--mcat-accent) 40%, var(--mcat-border));
        background: color-mix(in srgb, var(--mcat-accent) 8%, var(--mcat-surface));
        border-radius: 16px;
        padding: 16px 18px;
        transition:
            transform 0.1s ease,
            box-shadow 0.14s ease;
    }
    .cta:hover {
        transform: translateY(-2px);
        box-shadow: 0 12px 26px -14px
            color-mix(in srgb, var(--mcat-accent) 55%, transparent);
    }
    .cta-eyebrow {
        font-size: 11.5px;
        font-weight: 800;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--mcat-accent);
        margin-bottom: 4px;
    }
    .cta-title {
        font-size: 18px;
        font-weight: 800;
        color: var(--mcat-text);
    }
    .cta-sub {
        font-size: 13.5px;
        font-weight: 600;
        color: var(--mcat-muted);
        margin-top: 2px;
    }
    .link-card {
        display: block;
        width: 100%;
        text-align: right;
        appearance: none;
        cursor: pointer;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-surface);
        color: var(--mcat-accent);
        border-radius: 14px;
        padding: 14px 18px;
        font-size: 15px;
        font-weight: 700;
        margin-bottom: 14px;
    }
    .link-card:hover {
        background: var(--mcat-bg);
    }
</style>
