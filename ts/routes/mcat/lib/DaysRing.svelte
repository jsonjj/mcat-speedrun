<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Circular progress ring showing days remaining until the exam. The arc fills as
test day approaches (relative to a ~180-day horizon).
-->
<script lang="ts">
    export let days: number | null;

    const R = 52;
    const C = 2 * Math.PI * R;
    $: progress = days === null ? 0 : Math.max(0.04, Math.min(1, 1 - days / 180));
    $: dash = C * progress;
</script>

<div class="ring">
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
        <div class="num">{days === null ? "—" : days}</div>
        <div class="lab">{days === null ? "Set Exam Date" : "Days To Go"}</div>
    </div>
</div>

<style lang="scss">
    .ring {
        position: relative;
        width: 132px;
        height: 132px;
    }
    svg {
        width: 132px;
        height: 132px;
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
        transition: stroke-dasharray 0.4s ease;
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
        font-size: 32px;
        font-weight: 800;
        letter-spacing: -0.02em;
    }
    .lab {
        font-size: 12px;
        font-weight: 600;
        color: var(--mcat-muted);
        margin-top: 5px;
    }
</style>
