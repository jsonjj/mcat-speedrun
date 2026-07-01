<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A value range on a fixed scale: a track, a tinted low–high band, and a tick at
the point estimate. Optional min/mid/max scale labels underneath.
-->
<script lang="ts">
    export let min: number;
    export let max: number;
    export let low: number;
    export let high: number;
    export let point: number;
    export let color = "var(--mcat-accent)";
    export let scale = false;
    export let mid: number | null = null;

    $: span = Math.max(1, max - min);
    function pct(v: number): number {
        return Math.max(0, Math.min(100, ((v - min) / span) * 100));
    }
    $: lowPct = pct(low);
    $: highPct = pct(high);
    $: pointPct = pct(point);
    $: midVal = mid ?? Math.round((min + max) / 2);
</script>

<div class="rb">
    <div class="track">
        <div
            class="fill"
            style={`left:${lowPct}%;width:${Math.max(highPct - lowPct, 2)}%;background:${color}`}
        ></div>
        <div class="tick" style={`left:${pointPct}%;background:${color}`}></div>
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
    }
    .tick {
        position: absolute;
        top: -3px;
        bottom: -3px;
        width: 3px;
        border-radius: 2px;
        transform: translateX(-50%);
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
