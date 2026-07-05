<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A headline score card for the dashboard: evidence-tinted, icon + title, big
value, a range bar, and an evidence/sample-size footer. Tapping opens the
matching score detail page.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { cubicOut } from "svelte/easing";
    import { tweened } from "svelte/motion";

    import { evidence, toneVar } from "./blocks";
    import Icon from "./Icon.svelte";
    import RangeBar from "./RangeBar.svelte";
    import type { ScoreBlock } from "./types";

    export let id: "memory" | "performance" | "readiness";
    export let title: string;
    export let icon: string;
    export let block: ScoreBlock;
    export let scaleMin = 0;
    export let scaleMax = 100;
    // Optional "best next step" for this score, rendered inside the same tinted
    // box so it reads as this score's recommended action.
    export let next: { label: string; href: string } | null = null;

    $: ev = evidence(block);
    $: color = toneVar(ev.tone);

    function valueText(b: ScoreBlock): string {
        if (b.abstained) {
            return "—";
        }
        if (b.unit === "percent_recall" || b.unit === "percent_correct") {
            return `${Math.round(b.point ?? 0)}%`;
        }
        if (b.unit === "mcat_total" && b.low !== null && b.high !== null) {
            return `${Math.round(b.low)} – ${Math.round(b.high)}`;
        }
        return b.point !== null ? `${Math.round(b.point)}` : "—";
    }

    // Count the headline percent up on mount (and re-animate on change).
    const shownPct = tweened(0, { duration: 850, easing: cubicOut });
    $: isPct =
        !block.abstained &&
        (block.unit === "percent_recall" || block.unit === "percent_correct");
    $: shownPct.set(isPct ? (block.point ?? 0) : 0);
    $: value = isPct ? `${Math.round($shownPct)}%` : valueText(block);
    $: barLow = block.abstained ? scaleMin : (block.low ?? scaleMin);
    $: barHigh = block.abstained ? scaleMin : (block.high ?? scaleMin);
    $: barPoint = block.abstained ? scaleMin : (block.point ?? scaleMin);
</script>

<div class="ev" style={`--ev:${color}`}>
    <button class="ev-main" on:click={() => goto(`/mcat/score?id=${id}`)}>
        <div class="top">
            <div class="left">
                <span class="ic"><Icon name={icon} size={22} /></span>
                <span class="title">{title}</span>
            </div>
            <div class="value">{value}</div>
        </div>

        <RangeBar
            min={scaleMin}
            max={scaleMax}
            low={barLow}
            high={barHigh}
            point={barPoint}
            {color}
        />

        <div class="foot">
            {#if block.abstained}
                <span class="abstain">
                    Abstaining — {block.missing ?? "not enough evidence"}
                </span>
            {:else}
                <span class="dot"></span>
                <strong>{ev.label}</strong>
                {#if block.count != null}
                    <span class="count">· {block.count} {block.count_unit}</span>
                {/if}
            {/if}
        </div>
    </button>

    {#if next}
        <a class="ev-next" href={next.href}>
            <span class="ev-next-lab">Best next step</span>
            <span class="ev-next-val">
                {next.label}
                <Icon name="arrow" size={17} />
            </span>
        </a>
    {/if}
</div>

<style lang="scss">
    .ev {
        width: 100%;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        background: color-mix(in srgb, var(--ev) 9%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--ev) 24%, var(--mcat-border));
        border-radius: var(--mcat-radius);
        box-shadow: var(--mcat-shadow);
        transition:
            transform 0.1s ease,
            box-shadow 0.14s ease;
    }
    .ev:hover {
        transform: translateY(-2px);
        box-shadow: 0 14px 32px -14px color-mix(in srgb, var(--ev) 55%, transparent);
    }
    .ev-main {
        appearance: none;
        text-align: left;
        cursor: pointer;
        width: 100%;
        display: flex;
        flex-direction: column;
        gap: 12px;
        background: transparent;
        border: none;
        padding: 18px 22px;
    }
    /* The recommended action, inside the same tinted box (divider above). */
    .ev-next {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        text-decoration: none;
        padding: 12px 22px;
        border-top: 1px solid color-mix(in srgb, var(--ev) 26%, var(--mcat-border));
        background: color-mix(in srgb, var(--ev) 6%, transparent);
        transition: background 0.12s ease;
    }
    .ev-next:hover {
        background: color-mix(in srgb, var(--ev) 16%, transparent);
    }
    .ev-next-lab {
        font-size: 12px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mcat-muted);
        white-space: nowrap;
    }
    .ev-next-val {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 15.5px;
        font-weight: 800;
        color: var(--ev);
        text-align: right;
    }
    .top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
    }
    .left {
        display: flex;
        align-items: center;
        gap: 10px;
    }
    .ic {
        display: inline-flex;
        color: var(--ev);
    }
    .title {
        font-weight: 700;
        font-size: 18px;
        color: var(--mcat-text);
    }
    .value {
        font-size: 36px;
        font-weight: 800;
        letter-spacing: -0.02em;
        color: var(--ev);
        font-variant-numeric: tabular-nums;
    }
    .foot {
        display: flex;
        align-items: center;
        gap: 7px;
        font-size: 13.5px;
        color: var(--mcat-muted);
    }
    .foot strong {
        color: var(--ev);
        font-weight: 700;
    }
    .dot {
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: var(--ev);
    }
    .abstain {
        color: var(--ev);
        font-weight: 600;
    }
</style>
