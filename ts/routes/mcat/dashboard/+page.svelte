<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { SECTION_WORD, bestNextStep, evidence, toneVar } from "../lib/blocks";
    import CtaSquare from "../lib/CtaSquare.svelte";
    import EvidenceCard from "../lib/EvidenceCard.svelte";
    import Icon from "../lib/Icon.svelte";
    import RangeBar from "../lib/RangeBar.svelte";
    import { soundOn } from "../lib/sound";
    import Switch from "../lib/Switch.svelte";
    import { darkMode } from "../lib/theme";
    import type { DashboardData, ScoreBlock } from "../lib/types";

    const SECTION_ORDER = ["bb", "cp", "ps", "cars"];

    let data: DashboardData | null = null;
    let loading = true;
    let busy = false;

    async function load(): Promise<void> {
        loading = true;
        data = await postJson<DashboardData>("mcatDashboard");
        loading = false;
    }

    async function bootstrap(): Promise<void> {
        busy = true;
        try {
            await postJson("mcatBootstrap");
            await load();
        } finally {
            busy = false;
        }
    }

    function daysUntil(iso: string | null): number | null {
        if (!iso) {
            return null;
        }
        const exam = new Date(iso + "T00:00:00");
        if (isNaN(exam.getTime())) {
            return null;
        }
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return Math.max(0, Math.round((exam.getTime() - today.getTime()) / 86400000));
    }

    onMount(load);

    $: sectionReadiness = data?.scores
        ? SECTION_ORDER.map((c) => ({
              code: c,
              r: data!.scores!.sections[c]?.readiness as ScoreBlock | undefined,
          }))
              .filter((x) => x.r)
              .map((x) => ({ code: x.code, r: x.r as ScoreBlock }))
        : [];
    $: allReady =
        sectionReadiness.length === 4 && sectionReadiness.every((x) => !x.r.abstained);
    $: estLow = allReady ? sectionReadiness.reduce((s, x) => s + (x.r.low ?? 0), 0) : 0;
    $: estHigh = allReady
        ? sectionReadiness.reduce((s, x) => s + (x.r.high ?? 0), 0)
        : 0;
    $: days = daysUntil(data?.profile.exam_date ?? null);
    // Timeline: how far into the ~180-day prep window we are.
    const EXAM_HORIZON = 180;
    $: daysIn = days == null ? 0 : Math.max(0, EXAM_HORIZON - days);
    $: examPct =
        days == null ? 0 : Math.max(4, Math.min(96, (daysIn / EXAM_HORIZON) * 100));

    // The best next step for each score — the SAME target its detail page uses,
    // so the small link under each card and the detail page always agree.
    $: nextSteps = data?.scores
        ? {
              memory: bestNextStep(data.scores, "memory"),
              performance: bestNextStep(data.scores, "performance"),
              readiness: bestNextStep(data.scores, "readiness"),
          }
        : null;

    // The big adaptive "what to do next" CTA at the top: take the diagnostic if
    // it was skipped, else finish Today's Path, else move to Extra Practice.
    $: diagnosticDone = data?.profile.diagnostic_done ?? true;
    $: unlocked = data?.free_practice_unlocked ?? false;
    $: rm = data?.roadmap ?? { done: 0, total: 0 };
    $: doNext = !diagnosticDone
        ? {
              eyebrow: "Start here",
              title: "Take your diagnostic",
              sub: "A quick placement test seeds your three scores.",
              href: "/mcat/diagnostic",
              icon: "target",
          }
        : unlocked
          ? {
                eyebrow: "Today's path is done ✓",
                title: "Do Extra Practice",
                sub: "Sharpen your weak areas with targeted sets.",
                href: "/mcat/extra",
                icon: "spark",
            }
          : {
                eyebrow: "Start here",
                title: rm.done > 0 ? "Continue Today's Path" : "Start Today's Path",
                sub:
                    rm.total > 0
                        ? `${rm.done} of ${rm.total} blocks done · unlocks Extra Practice`
                        : "Your guided plan for today.",
                href: "/mcat/roadmap",
                icon: "target",
            };
    $: rmPct = rm.total > 0 ? (rm.done / rm.total) * 100 : 0;
    $: showProgress = diagnosticDone && !unlocked && rm.total > 0;
</script>

<div class="mcat-container">
    <header class="head">
        <div>
            <h1 class="mcat-title">Dashboard</h1>
            <p class="mcat-subtitle">Three measures, with evidence.</p>
        </div>
        <div class="toggles">
            <div class="theme-toggle">
                <Icon name={$soundOn ? "sound" : "mute"} size={18} />
                <span>Sound</span>
                <Switch
                    checked={$soundOn}
                    label="Sound effects"
                    on:toggle={() => soundOn.update((v) => !v)}
                />
            </div>
            <div class="theme-toggle">
                <Icon name={$darkMode ? "moon" : "sun"} size={18} />
                <span>Dark Mode</span>
                <Switch
                    checked={$darkMode}
                    label="Dark mode"
                    on:toggle={() => darkMode.update((v) => !v)}
                />
            </div>
        </div>
    </header>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if !data?.has_content}
        <div class="mcat-card empty">
            <h2>Set up your MCAT deck</h2>
            <p class="mcat-muted">Install the starter content to begin.</p>
            <button
                class="mcat-btn mcat-btn-primary"
                disabled={busy}
                on:click={bootstrap}
            >
                {busy ? "Installing…" : "Install starter content"}
            </button>
        </div>
    {:else if data.scores}
        <div class="grid">
            <section class="evcards">
                <EvidenceCard
                    id="memory"
                    title="Memory Recall"
                    icon="brain"
                    block={data.scores.memory}
                    next={nextSteps?.memory ?? null}
                />
                <EvidenceCard
                    id="performance"
                    title="Applied Under Exam Conditions"
                    icon="target"
                    block={data.scores.performance}
                    next={nextSteps?.performance ?? null}
                />
                <EvidenceCard
                    id="readiness"
                    title="Overall Readiness"
                    icon="gauge"
                    block={data.scores.readiness}
                    scaleMin={472}
                    scaleMax={528}
                    next={nextSteps?.readiness ?? null}
                />
            </section>

            <div class="rightcol">
                <CtaSquare
                    eyebrow={doNext.eyebrow}
                    title={doNext.title}
                    sub={doNext.sub}
                    icon={doNext.icon}
                    href={doNext.href}
                    green={unlocked}
                    done={unlocked}
                    progress={showProgress ? rmPct / 100 : null}
                />

                <div class="exam-card">
                    <div class="exam-main">
                        <div class="exam-top">
                            <span class="exam-num">{days ?? "—"}</span>
                            <span class="exam-lab">days to go</span>
                        </div>
                        <div class="exam-track">
                            <div class="exam-fill" style={`width:${examPct}%`}></div>
                            <div class="exam-end"></div>
                            <div class="exam-knob" style={`left:${examPct}%`}></div>
                        </div>
                        <div class="exam-marks">
                            <span class="m-edge">started</span>
                            {#if days != null}
                                <span class="m-now" style={`left:${examPct}%`}>
                                    {daysIn} days in
                                </span>
                            {/if}
                            <span class="m-edge m-right">exam day</span>
                        </div>
                    </div>
                    <div class="exam-sep"></div>
                    <div class="streak-box">
                        <span class="streak-fire">🔥</span>
                        <div class="streak-txt">
                            <span class="streak-n">{data.streak.count}</span>
                            <span class="streak-l">day streak</span>
                        </div>
                    </div>
                </div>

                <button class="estimate" on:click={() => goto("/mcat/breakdown")}>
                    <div class="est-top">
                        <span class="est-title">Score Estimate</span>
                        <span class="est-total">
                            {allReady ? `${estLow} – ${estHigh}` : "Building"}
                        </span>
                    </div>
                    {#if allReady}
                        <div class="est-sections">
                            {#each sectionReadiness as { code, r } (code)}
                                <div class="est-row">
                                    <span class="est-name">{SECTION_WORD[code]}</span>
                                    <div class="est-bar">
                                        <RangeBar
                                            min={118}
                                            max={132}
                                            low={r.low ?? 118}
                                            high={r.high ?? 118}
                                            point={r.point ?? 118}
                                            color={toneVar(evidence(r).tone)}
                                        />
                                    </div>
                                    <span class="est-range">
                                        {Math.round(r.low ?? 0)} – {Math.round(
                                            r.high ?? 0,
                                        )}
                                    </span>
                                </div>
                            {/each}
                        </div>
                    {:else}
                        <p class="est-note">
                            Keep practicing — the estimate sharpens as evidence builds.
                        </p>
                    {/if}
                    <div class="est-link">
                        See Full Breakdown <Icon name="arrow" size={16} />
                    </div>
                </button>
            </div>
        </div>
    {/if}
</div>

<style lang="scss">
    .head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
        margin-bottom: 18px;
    }
    .toggles {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
    }
    .theme-toggle {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 999px;
        padding: 7px 8px 7px 14px;
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-text);
    }
    .empty {
        max-width: 520px;
    }
    .empty h2 {
        margin-top: 0;
    }
    .grid {
        display: grid;
        grid-template-columns: 1.05fr 0.95fr;
        gap: 16px;
        align-items: stretch;
    }
    @media (max-width: 900px) {
        .grid {
            grid-template-columns: 1fr;
        }
    }
    /* Both columns fill the same height; cards grow evenly (tight gaps, no
       big spacers) so the two columns' tops AND bottoms line up. */
    .evcards {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .evcards :global(.ev) {
        flex: 1;
    }
    .rightcol {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .rightcol .estimate {
        flex: 1;
    }
    /* Days-to-go timeline + streak block. */
    .exam-card {
        display: flex;
        align-items: center;
        gap: 20px;
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 18px;
        padding: 16px 20px;
        box-shadow: var(--mcat-shadow);
    }
    .exam-main {
        flex: 1;
        min-width: 0;
    }
    .exam-top {
        display: flex;
        align-items: baseline;
        gap: 8px;
        margin-bottom: 14px;
    }
    .exam-num {
        font-size: 28px;
        font-weight: 800;
        letter-spacing: -0.02em;
        color: var(--mcat-text);
        font-variant-numeric: tabular-nums;
    }
    .exam-lab {
        font-size: 15px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .exam-track {
        position: relative;
        height: 8px;
        border-radius: 999px;
        background: var(--mcat-track);
    }
    .exam-fill {
        position: absolute;
        left: 0;
        top: 0;
        height: 100%;
        border-radius: 999px;
        background: var(--mcat-accent);
    }
    .exam-end {
        position: absolute;
        right: -2px;
        top: 50%;
        width: 11px;
        height: 11px;
        border-radius: 3px;
        background: var(--mcat-surface);
        border: 2px solid var(--mcat-border);
        transform: translate(0, -50%);
    }
    .exam-knob {
        position: absolute;
        top: 50%;
        width: 16px;
        height: 16px;
        border-radius: 50%;
        background: var(--mcat-surface);
        border: 3px solid var(--mcat-accent);
        transform: translate(-50%, -50%);
        box-shadow: 0 2px 6px rgba(16, 24, 40, 0.18);
    }
    .exam-marks {
        position: relative;
        margin-top: 9px;
        height: 15px;
        font-size: 12px;
        font-weight: 700;
        color: var(--mcat-muted);
    }
    .m-edge {
        position: absolute;
        left: 0;
    }
    .m-right {
        left: auto;
        right: 0;
    }
    .m-now {
        position: absolute;
        transform: translateX(-50%);
        white-space: nowrap;
        color: var(--mcat-accent);
    }
    .exam-sep {
        align-self: stretch;
        width: 1px;
        background: var(--mcat-border);
    }
    .streak-box {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-shrink: 0;
        background: color-mix(in srgb, var(--mcat-amber) 15%, transparent);
        border-radius: 14px;
        padding: 11px 18px;
    }
    .streak-fire {
        font-size: 22px;
    }
    .streak-txt {
        display: flex;
        flex-direction: column;
        line-height: 1.08;
    }
    .streak-n {
        font-size: 22px;
        font-weight: 800;
        color: var(--mcat-amber);
        font-variant-numeric: tabular-nums;
    }
    .streak-l {
        font-size: 12px;
        font-weight: 700;
        color: var(--mcat-amber);
        opacity: 0.9;
    }
    .estimate {
        appearance: none;
        cursor: pointer;
        text-align: left;
        display: flex;
        flex-direction: column;
        width: 100%;
        /* Don't inherit Anki's button color (--fg), which is dark in dark mode. */
        color: var(--mcat-text);
        background: color-mix(in srgb, var(--mcat-accent) 8%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--mcat-accent) 22%, var(--mcat-border));
        border-radius: var(--mcat-radius);
        padding: 22px;
        box-shadow: var(--mcat-shadow);
        transition:
            transform 0.1s ease,
            box-shadow 0.14s ease;
    }
    .estimate:hover {
        transform: translateY(-2px);
        background: color-mix(in srgb, var(--mcat-accent) 13%, var(--mcat-surface));
        box-shadow: 0 14px 32px -14px
            color-mix(in srgb, var(--mcat-accent) 50%, transparent);
    }
    .est-top {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 16px;
    }
    .est-title {
        font-size: 18px;
        font-weight: 800;
    }
    .est-total {
        font-size: 30px;
        font-weight: 800;
        letter-spacing: -0.02em;
        color: var(--mcat-accent);
        font-variant-numeric: tabular-nums;
    }
    .est-sections {
        display: flex;
        flex-direction: column;
        gap: 13px;
    }
    .est-row {
        display: grid;
        grid-template-columns: 92px 1fr 78px;
        align-items: center;
        gap: 12px;
    }
    .est-name {
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-text);
    }
    .est-range {
        font-size: 13px;
        font-weight: 700;
        text-align: right;
        color: var(--mcat-muted);
        font-variant-numeric: tabular-nums;
    }
    .est-note {
        margin: 0;
        font-size: 14px;
        color: var(--mcat-muted);
    }
    .est-link {
        display: flex;
        align-items: center;
        gap: 5px;
        justify-content: flex-end;
        margin-top: auto;
        padding-top: 16px;
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-accent);
    }
</style>
