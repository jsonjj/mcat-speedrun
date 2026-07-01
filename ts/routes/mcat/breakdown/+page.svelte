<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Full score report: per-section estimated ranges on the 118–132 scale, colored by
evidence strength, plus the 472–528 total.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { SECTION_WORD, evidence, toneVar } from "../lib/blocks";
    import Icon from "../lib/Icon.svelte";
    import RangeBar from "../lib/RangeBar.svelte";
    import type { DashboardData, ScoreBlock } from "../lib/types";

    const SECTIONS: { code: string; icon: string }[] = [
        { code: "cars", icon: "book" },
        { code: "cp", icon: "flask" },
        { code: "bb", icon: "atom" },
        { code: "ps", icon: "smiley" },
    ];

    let data: DashboardData | null = null;
    let loading = true;

    async function load(): Promise<void> {
        loading = true;
        data = await postJson<DashboardData>("mcatDashboard");
        loading = false;
    }

    function back(): void {
        if (history.length > 1) {
            history.back();
        } else {
            goto("/mcat/dashboard");
        }
    }

    onMount(load);

    $: rows = data?.scores
        ? SECTIONS.map((s) => ({
              code: s.code,
              icon: s.icon,
              r: data!.scores!.sections[s.code]?.readiness as ScoreBlock | undefined,
          }))
              .filter((x) => x.r)
              .map((x) => ({ code: x.code, icon: x.icon, r: x.r as ScoreBlock }))
        : [];
    $: ready = rows.filter((x) => !x.r.abstained);
    $: allReady = rows.length === 4 && ready.length === 4;
    $: total = allReady
        ? {
              low: ready.reduce((s, x) => s + (x.r.low ?? 0), 0),
              high: ready.reduce((s, x) => s + (x.r.high ?? 0), 0),
              point: ready.reduce((s, x) => s + (x.r.point ?? 0), 0),
          }
        : null;
</script>

<div class="mcat-container narrow">
    <button class="back" on:click={back}>← Back</button>
    <h1 class="mcat-title">Your Score Estimate</h1>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if rows.length === 0}
        <div class="mcat-card mcat-muted">
            No section estimates yet — do some practice to build them.
        </div>
    {:else}
        <div class="sections">
            {#each rows as { code, icon, r } (code)}
                {@const ev = evidence(r)}
                {@const color = toneVar(ev.tone)}
                <div class="sec" style={`--ev:${color}`}>
                    <div class="sec-top">
                        <span class="sec-name">
                            <span class="sec-ic"><Icon name={icon} size={20} /></span>
                            {SECTION_WORD[code]}
                        </span>
                        <span class="sec-range">
                            {r.abstained
                                ? "—"
                                : `${Math.round(r.low ?? 0)} – ${Math.round(r.high ?? 0)}`}
                        </span>
                    </div>
                    <RangeBar
                        min={118}
                        max={132}
                        low={r.abstained ? 118 : (r.low ?? 118)}
                        high={r.abstained ? 118 : (r.high ?? 118)}
                        point={r.abstained ? 118 : (r.point ?? 118)}
                        {color}
                        scale={true}
                    />
                </div>
            {/each}
        </div>

        <div class="total">
            <div class="total-cap">Total · 472–528 Scale</div>
            <div class="total-big">
                {total
                    ? `${Math.round(total.low)} – ${Math.round(total.high)}`
                    : "Building"}
            </div>
            {#if total}
                <RangeBar
                    min={472}
                    max={528}
                    low={total.low}
                    high={total.high}
                    point={total.point}
                    color="var(--mcat-accent)"
                    scale={true}
                    mid={500}
                />
            {/if}
        </div>

        <div class="legend">
            <span>
                <span class="dot" style="background:var(--mcat-green)"></span>
                Strong Evidence
            </span>
            <span>
                <span class="dot" style="background:var(--mcat-amber)"></span>
                Moderate Evidence
            </span>
            <span>
                <span class="dot" style="background:var(--mcat-red)"></span>
                Thin Evidence
            </span>
        </div>
    {/if}
</div>

<style lang="scss">
    .narrow {
        max-width: 900px;
    }
    .back {
        appearance: none;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-surface);
        color: var(--mcat-text);
        border-radius: 9px;
        padding: 8px 14px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        margin-bottom: 16px;
    }
    .back:hover {
        background: var(--mcat-bg);
    }
    .mcat-title {
        margin-bottom: 20px;
    }
    .sections {
        display: flex;
        flex-direction: column;
        gap: 16px;
        margin-bottom: 18px;
    }
    .sec {
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: var(--mcat-radius);
        box-shadow: var(--mcat-shadow);
        padding: 18px 20px;
    }
    .sec-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 14px;
    }
    .sec-name {
        display: flex;
        align-items: center;
        gap: 10px;
        font-weight: 700;
        font-size: 16px;
    }
    .sec-ic {
        display: inline-flex;
        color: var(--ev);
    }
    .sec-range {
        font-size: 26px;
        font-weight: 800;
        letter-spacing: -0.02em;
        color: var(--ev);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
    }
    .total {
        background: color-mix(in srgb, var(--mcat-accent) 8%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--mcat-accent) 22%, var(--mcat-border));
        border-radius: var(--mcat-radius);
        padding: 22px;
        margin-bottom: 16px;
    }
    .total-cap {
        font-size: 14px;
        font-weight: 700;
        color: var(--mcat-accent);
        margin-bottom: 6px;
    }
    .total-big {
        font-size: 46px;
        font-weight: 800;
        letter-spacing: -0.03em;
        color: var(--mcat-accent);
        line-height: 1;
        margin-bottom: 16px;
        font-variant-numeric: tabular-nums;
    }
    .legend {
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
        font-size: 13px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .legend span {
        display: inline-flex;
        align-items: center;
        gap: 7px;
    }
    .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        display: inline-block;
    }
</style>
