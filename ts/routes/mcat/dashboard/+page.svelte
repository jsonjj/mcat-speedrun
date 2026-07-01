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
                />
                <EvidenceCard
                    id="performance"
                    title="Applied Under Exam Conditions"
                    icon="target"
                    block={data.scores.performance}
                />
                <EvidenceCard
                    id="readiness"
                    title="Overall Readiness"
                    icon="gauge"
                    block={data.scores.readiness}
                    scaleMin={472}
                    scaleMax={528}
                />
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
        align-items: start;
    }
    @media (max-width: 900px) {
        .grid {
            grid-template-columns: 1fr;
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
</style>
