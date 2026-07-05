<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Tiny trend sparkline (a normalized polyline) for the account progress cards.
Values are percents (0–100); the line is scaled to its own min/max so small
real movements are still visible. Draws itself in on mount.
-->
<script lang="ts">
    export let points: number[] = [];
    export let color = "var(--mcat-accent)";

    const W = 100;
    const H = 30;
    const PAD = 3;

    $: lo = points.length ? Math.min(...points) : 0;
    $: hi = points.length ? Math.max(...points) : 100;
    $: span = hi - lo || 1;
    $: coords =
        points.length > 1
            ? points.map((p, i) => {
                  const x = (i / (points.length - 1)) * (W - PAD * 2) + PAD;
                  const y = H - PAD - ((p - lo) / span) * (H - PAD * 2);
                  return `${x.toFixed(1)},${y.toFixed(1)}`;
              })
            : [];
    $: line = coords.join(" ");
    $: area = coords.length ? `${PAD},${H} ${line} ${W - PAD},${H}` : "";
    $: last = coords.length ? coords[coords.length - 1].split(",") : null;
</script>

{#if points.length > 1}
    <svg
        class="spark"
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        style={`--c:${color}`}
    >
        <polygon class="fill" points={area} />
        <polyline class="stroke" points={line} vector-effect="non-scaling-stroke" />
        {#if last}
            <circle class="tip" cx={last[0]} cy={last[1]} r="2.5" />
        {/if}
    </svg>
{/if}

<style lang="scss">
    .spark {
        width: 100%;
        height: 30px;
        display: block;
        overflow: visible;
    }
    .stroke {
        fill: none;
        stroke: var(--c);
        stroke-width: 2;
        stroke-linecap: round;
        stroke-linejoin: round;
        stroke-dasharray: 260;
        stroke-dashoffset: 260;
        animation: spark-draw 0.9s ease forwards 0.1s;
    }
    .fill {
        fill: var(--c);
        opacity: 0.12;
    }
    .tip {
        fill: var(--c);
        opacity: 0;
        animation: spark-tip 0.3s ease forwards 0.9s;
    }
    @keyframes spark-draw {
        to {
            stroke-dashoffset: 0;
        }
    }
    @keyframes spark-tip {
        to {
            opacity: 1;
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .stroke {
            stroke-dashoffset: 0;
            animation: none;
        }
        .tip {
            opacity: 1;
            animation: none;
        }
    }
</style>
