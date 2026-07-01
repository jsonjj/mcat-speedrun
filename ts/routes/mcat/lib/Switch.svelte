<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { createEventDispatcher } from "svelte";

    export let checked = false;
    export let label = "Toggle";
    const dispatch = createEventDispatcher<{ toggle: boolean }>();
</script>

<button
    type="button"
    class="sw"
    class:on={checked}
    role="switch"
    aria-checked={checked}
    aria-label={label}
    on:click={() => dispatch("toggle", !checked)}
>
    <span class="knob"></span>
</button>

<style lang="scss">
    .sw {
        appearance: none;
        border: none;
        cursor: pointer;
        width: 46px;
        height: 26px;
        border-radius: 999px;
        background: var(--mcat-track);
        position: relative;
        padding: 0;
        transition: background 0.16s ease;
    }
    .sw.on {
        background: var(--mcat-accent);
    }
    .knob {
        position: absolute;
        top: 3px;
        left: 3px;
        width: 20px;
        height: 20px;
        border-radius: 50%;
        background: #fff;
        box-shadow: 0 1px 3px rgba(16, 24, 40, 0.3);
        transition: transform 0.16s ease;
    }
    .sw.on .knob {
        transform: translateX(20px);
    }
</style>
