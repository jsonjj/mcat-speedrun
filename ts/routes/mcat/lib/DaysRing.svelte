<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Circular progress ring showing days remaining until the exam. The arc fills as
test day approaches (relative to a ~180-day horizon).
-->
<script lang="ts">
    import { cubicOut } from "svelte/easing";
    import { tweened } from "svelte/motion";

    export let days: number | null;
    export let size = 132;

    const R = 52;
    const C = 2 * Math.PI * R;
    // Draw the arc and count the number up on mount (and re-animate on change).
    const drawn = tweened(0, { duration: 950, easing: cubicOut });
    const shownDays = tweened(0, { duration: 950, easing: cubicOut });
    $: progress = days === null ? 0 : Math.max(0.04, Math.min(1, 1 - days / 180));
    $: drawn.set(progress);
    $: if (days !== null) {
        shownDays.set(days);
    }
    $: dash = C * $drawn;
</script>

<div class="ring" style={`--rs:${size}px`}>
    <svg viewBox="0 0 120 120">
        <circle cx="60" cy="60" r={R} class="track" />
        <circle
            cx="60"
            cy="60"
            r={R}
            class="prog"
            stroke-dasharray={`${dash} ${C}`}
            transform="rotate(-90 60 60)"
        />
    </svg>
    <div class="center">
        <div class="num">{days === null ? "—" : Math.round($shownDays)}</div>
        <div class="lab">{days === null ? "Set Exam Date" : "Days To Go"}</div>
    </div>
</div>

<style lang="scss">
    .ring {
        position: relative;
        width: var(--rs);
        height: var(--rs);
    }
    svg {
        width: var(--rs);
        height: var(--rs);
        display: block;
    }
    .track {
        fill: none;
        stroke: var(--mcat-track);
        stroke-width: 9;
    }
    .prog {
        fill: none;
        stroke: var(--mcat-accent);
        stroke-width: 9;
        stroke-linecap: round;
    }
    .center {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        line-height: 1;
    }
    .num {
        font-size: calc(var(--rs) * 0.24);
        font-weight: 800;
        letter-spacing: -0.02em;
    }
    .lab {
        font-size: calc(var(--rs) * 0.092);
        font-weight: 600;
        color: var(--mcat-muted);
        margin-top: 5px;
    }
</style>
