<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { SECTION_WORD, evidence, toneVar } from "../lib/blocks";
    import DaysRing from "../lib/DaysRing.svelte";
    import EvidenceCard from "../lib/EvidenceCard.svelte";
    import Icon from "../lib/Icon.svelte";
    import RangeBar from "../lib/RangeBar.svelte";
    import { soundOn } from "../lib/sound";
    import Switch from "../lib/Switch.svelte";
    import { darkMode } from "../lib/theme";
    import type { DashboardData, Scores, ScoreBlock } from "../lib/types";

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

    // Highlight the weakest / strongest score by evidence strength (matching the
    // card colors), plus "Not enough data" on abstained ones. Press a badge for a
    // one-line explanation — no AI, computed straight from the scores.
    type Measure = "memory" | "performance";
    type Badge = {
        kind: "weakest" | "strongest" | "nodata";
        label: string;
        text: string;
        link?: { href: string; label: string };
    };

    function toneRank(b: ScoreBlock): number {
        const t = evidence(b).tone;
        if (t === "green") {
            return 2;
        }
        if (t === "amber") {
            return 1;
        }
        return 0;
    }

    // Sections ranked (ascending) by a measure, skipping abstained ones.
    function sectionsByMeasure(
        s: Scores,
        measure: Measure,
    ): { code: string; point: number }[] {
        const out: { code: string; point: number }[] = [];
        for (const code of SECTION_ORDER) {
            const sec = s.sections[code];
            if (!sec) {
                continue;
            }
            const b = measure === "memory" ? sec.memory : sec.performance;
            if (b && !b.abstained && b.point != null) {
                out.push({ code, point: b.point });
            }
        }
        out.sort((a, b) => a.point - b.point);
        return out;
    }

    function practiceHref(measure: Measure, code: string): string {
        return measure === "memory"
            ? `/mcat/flashcards?section=${code}`
            : `/mcat/mini?section=${code}`;
    }

    function computeBadges(s: Scores | null, unlocked: boolean): Record<string, Badge> {
        const out: Record<string, Badge> = {};
        if (!s) {
            return out;
        }
        if (s.readiness.abstained) {
            out.readiness = {
                kind: "nodata",
                label: "Not enough data",
                text: "Not enough reviews yet to project a score.",
            };
        }
        const measurable: { id: Measure; rank: number; point: number }[] = [];
        if (s.memory.abstained) {
            out.memory = {
                kind: "nodata",
                label: "Not enough data",
                text: "Do some flashcards to measure recall.",
            };
        } else {
            measurable.push({
                id: "memory",
                rank: toneRank(s.memory),
                point: s.memory.point ?? 0,
            });
        }
        if (s.performance.abstained) {
            out.performance = {
                kind: "nodata",
                label: "Not enough data",
                text: "Do a question set to measure applied accuracy.",
            };
        } else {
            measurable.push({
                id: "performance",
                rank: toneRank(s.performance),
                point: s.performance.point ?? 0,
            });
        }
        if (measurable.length === 2) {
            measurable.sort((a, b) => a.rank - b.rank || a.point - b.point);
            const weakId = measurable[0].id;
            const strongId = measurable[1].id;

            const strong = sectionsByMeasure(s, strongId);
            const topNames = strong
                .slice(-2)
                .reverse()
                .map((x) => SECTION_WORD[x.code] ?? x.code);
            out[strongId] = {
                kind: "strongest",
                label: "Strongest",
                text: topNames.length
                    ? `Strongest: ${topNames.join(", ")}.`
                    : "Your strongest area so far.",
            };

            const weak = sectionsByMeasure(s, weakId);
            const w = weak[0];
            if (w) {
                const name = SECTION_WORD[w.code] ?? w.code;
                const practice =
                    weakId === "memory" ? `${name} flashcards` : `${name} problems`;
                out[weakId] = {
                    kind: "weakest",
                    label: "Weakest",
                    text: unlocked
                        ? `Weakest: ${name}. Practice ${practice} next.`
                        : `Weakest: ${name}. Finish today's path to unlock practice.`,
                    link: unlocked
                        ? {
                              href: practiceHref(weakId, w.code),
                              label: `Start ${practice} →`,
                          }
                        : undefined,
                };
            } else {
                out[weakId] = {
                    kind: "weakest",
                    label: "Weakest",
                    text: "Your weakest area — study here next.",
                };
            }
        }
        return out;
    }

    $: badges = computeBadges(
        data?.scores ?? null,
        data?.free_practice_unlocked ?? false,
    );
    let openInfo: string | null = null;
    function toggleInfo(id: string): void {
        openInfo = openInfo === id ? null : id;
    }
</script>

<svelte:window on:click={() => (openInfo = null)} />

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
                <div class="ev-wrap">
                    {#if badges.memory}
                        <button
                            class="badge {badges.memory.kind}"
                            on:click|stopPropagation={() => toggleInfo("memory")}
                        >
                            {badges.memory.label}
                            <span class="badge-i">i</span>
                        </button>
                        {#if openInfo === "memory"}
                            <div class="popover">
                                {badges.memory.text}
                                {#if badges.memory.link}
                                    <a
                                        class="popover-link"
                                        href={badges.memory.link.href}
                                    >
                                        {badges.memory.link.label}
                                    </a>
                                {/if}
                            </div>
                        {/if}
                    {/if}
                    <EvidenceCard
                        id="memory"
                        title="Memory Recall"
                        icon="brain"
                        block={data.scores.memory}
                    />
                </div>
                <div class="ev-wrap">
                    {#if badges.performance}
                        <button
                            class="badge {badges.performance.kind}"
                            on:click|stopPropagation={() => toggleInfo("performance")}
                        >
                            {badges.performance.label}
                            <span class="badge-i">i</span>
                        </button>
                        {#if openInfo === "performance"}
                            <div class="popover">
                                {badges.performance.text}
                                {#if badges.performance.link}
                                    <a
                                        class="popover-link"
                                        href={badges.performance.link.href}
                                    >
                                        {badges.performance.link.label}
                                    </a>
                                {/if}
                            </div>
                        {/if}
                    {/if}
                    <EvidenceCard
                        id="performance"
                        title="Applied Under Exam Conditions"
                        icon="target"
                        block={data.scores.performance}
                    />
                </div>
                <div class="ev-wrap">
                    {#if badges.readiness}
                        <button
                            class="badge {badges.readiness.kind}"
                            on:click|stopPropagation={() => toggleInfo("readiness")}
                        >
                            {badges.readiness.label}
                            <span class="badge-i">i</span>
                        </button>
                        {#if openInfo === "readiness"}
                            <div class="popover">{badges.readiness.text}</div>
                        {/if}
                    {/if}
                    <EvidenceCard
                        id="readiness"
                        title="Overall Readiness"
                        icon="gauge"
                        block={data.scores.readiness}
                        scaleMin={472}
                        scaleMax={528}
                    />
                </div>
            </section>

            <div class="rightcol">
                <div class="ring-wrap">
                    <DaysRing {days} />
                    {#if data.streak.count > 0}
                        <div class="streak">🔥 {data.streak.count}-day streak</div>
                    {/if}
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
        gap: 18px;
        align-items: center;
        /* Fill the viewport so the page isn't top-stacked with blank below. */
        min-height: calc(100dvh - 190px);
    }
    @media (max-width: 900px) {
        .grid {
            grid-template-columns: 1fr;
            align-items: stretch;
            min-height: 0;
        }
    }
    .evcards {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .rightcol {
        display: flex;
        flex-direction: column;
        gap: 16px;
    }
    .ring-wrap {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
    }
    .streak {
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-amber);
    }
    .estimate {
        appearance: none;
        cursor: pointer;
        text-align: left;
        display: block;
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
        margin-top: 16px;
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-accent);
    }
    /* Weakest / Strongest / Not-enough-data badges on the score cards, each
       pressable for a one-line popup. */
    .ev-wrap {
        position: relative;
    }
    .badge {
        position: absolute;
        top: -10px;
        left: 16px;
        z-index: 3;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        appearance: none;
        cursor: pointer;
        border: none;
        border-radius: 999px;
        padding: 4px 10px;
        font-size: 12px;
        font-weight: 800;
        color: #fff;
        box-shadow: 0 4px 12px -4px rgba(16, 24, 40, 0.35);
    }
    .badge.weakest {
        background: var(--mcat-red);
    }
    .badge.strongest {
        background: var(--mcat-green);
    }
    .badge.nodata {
        background: var(--mcat-muted);
    }
    .badge-i {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 15px;
        height: 15px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.28);
        font-size: 10px;
        font-weight: 800;
        font-style: italic;
    }
    .popover {
        position: absolute;
        top: 18px;
        left: 16px;
        z-index: 5;
        width: min(280px, 80vw);
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 12px;
        box-shadow: var(--mcat-shadow);
        padding: 12px 14px;
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-text);
    }
    .popover-link {
        display: inline-block;
        margin-top: 8px;
        font-size: 13px;
        font-weight: 800;
        color: var(--mcat-accent);
        text-decoration: none;
    }
    .popover-link:hover {
        text-decoration: underline;
    }
</style>
