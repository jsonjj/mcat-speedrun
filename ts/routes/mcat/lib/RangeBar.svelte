<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A value range on a fixed scale: a track, a tinted low–high band, and a tick at
the point estimate. Optional min/mid/max scale labels underneath.
-->
<script lang="ts">
    import { onMount } from "svelte";

    export let min: number;
    export let max: number;
    export let low: number;
    export let high: number;
    export let point: number;
    export let color = "var(--mcat-accent)";
    export let scale = false;
    export let mid: number | null = null;

    // Grow the band out from the point on first paint (see .fill transition).
    let mounted = false;
    onMount(() => {
        mounted = true;
    });

    $: span = Math.max(1, max - min);
    function pct(v: number): number {
        return Math.max(0, Math.min(100, ((v - min) / span) * 100));
    }
    $: lowPct = pct(low);
    $: highPct = pct(high);
    $: pointPct = pct(point);
    $: bandW = Math.max(highPct - lowPct, 2);
    // Where the point sits inside the band, so scaleX grows outward from it.
    $: originPct = Math.max(0, Math.min(100, ((pointPct - lowPct) / bandW) * 100));
    $: midVal = mid ?? Math.round((min + max) / 2);
</script>

<div class="rb">
    <div class="track">
        <div
            class="fill"
            class:mounted
            style={`left:${lowPct}%;width:${bandW}%;background:${color};transform-origin:${originPct}% 50%`}
        ></div>
        <div
            class="tick"
            class:mounted
            style={`left:${pointPct}%;background:${color}`}
        ></div>
    </div>
    {#if scale}
        <div class="scale">
            <span>{min}</span>
            <span>{midVal}</span>
            <span>{max}</span>
        </div>
    {/if}
</div>

<style lang="scss">
    .track {
        position: relative;
        height: 12px;
        border-radius: 999px;
        background: var(--mcat-track);
    }
    .fill {
        position: absolute;
        top: 0;
        bottom: 0;
        border-radius: 999px;
        opacity: 0.5;
        transform: scaleX(0);
        transition:
            transform 0.7s cubic-bezier(0.2, 0.75, 0.25, 1),
            left 0.4s ease,
            width 0.4s ease;
    }
    .fill.mounted {
        transform: scaleX(1);
    }
    .tick {
        position: absolute;
        top: -3px;
        bottom: -3px;
        width: 3px;
        border-radius: 2px;
        transform: translateX(-50%) scaleY(0.3);
        opacity: 0;
        transition:
            transform 0.45s cubic-bezier(0.2, 0.9, 0.3, 1.3) 0.28s,
            opacity 0.3s ease 0.28s,
            left 0.4s ease;
    }
    .tick.mounted {
        transform: translateX(-50%) scaleY(1);
        opacity: 1;
    }
    @media (prefers-reduced-motion: reduce) {
        .fill {
            transition: none;
            transform: scaleX(1);
        }
        .tick {
            transition: none;
            opacity: 1;
            transform: translateX(-50%);
        }
    }
    .scale {
        display: flex;
        justify-content: space-between;
        margin-top: 7px;
        font-size: 12px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
</style>
