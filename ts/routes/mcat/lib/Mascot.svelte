<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A small friendly robot mascot used in the review flow. Kept as inline SVG so it
inherits the theme and animates cheaply.
-->
<script lang="ts">
    export let size = 96;
    export let mood: "happy" | "neutral" = "happy";
    export let color = "#5b5bd6";
</script>

<svg
    width={size}
    height={size}
    viewBox="0 0 120 120"
    fill="none"
    class="mascot"
    aria-hidden="true"
>
    <line
        x1="42"
        y1="27"
        x2="37"
        y2="12"
        stroke={color}
        stroke-width="4"
        stroke-linecap="round"
    />
    <line
        x1="78"
        y1="27"
        x2="83"
        y2="12"
        stroke={color}
        stroke-width="4"
        stroke-linecap="round"
    />
    <circle cx="36" cy="10" r="5" fill="#f2a33c" />
    <circle cx="84" cy="10" r="5" fill="#f2a33c" />
    <rect x="22" y="26" width="76" height="70" rx="26" fill={color} />
    <rect x="35" y="47" width="20" height="27" rx="10" fill="#fff" />
    <rect x="65" y="47" width="20" height="27" rx="10" fill="#fff" />
    <circle cx="46" cy="61" r="5.5" fill="#1f2340" />
    <circle cx="74" cy="61" r="5.5" fill="#1f2340" />
    {#if mood === "happy"}
        <path
            d="M45 82 Q60 93 75 82"
            stroke="#fff"
            stroke-width="4"
            stroke-linecap="round"
            fill="none"
        />
    {:else}
        <path
            d="M48 85 H72"
            stroke="#fff"
            stroke-width="4"
            stroke-linecap="round"
            fill="none"
        />
    {/if}
</svg>

<style>
    .mascot {
        display: block;
        flex: 0 0 auto;
    }
</style>
