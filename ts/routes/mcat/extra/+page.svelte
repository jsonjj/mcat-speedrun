<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Extra Practice: free choice — the full Mini-MCAT, any section's problems or
flashcards, plus the CARS debate. Locked until the day's required roadmap
blocks are complete, so the highest-value work always comes first.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { SECTION_COLOR, textColor } from "../lib/blocks";
    import Icon from "../lib/Icon.svelte";
    import { SECTION_NAMES } from "../lib/types";
    import type { RoadmapResponse } from "../lib/types";

    const SECTIONS = ["bb", "cp", "ps", "cars"];

    let unlocked = false;
    let loading = true;
    let phase = "";

    async function load(): Promise<void> {
        loading = true;
        const resp = await postJson<RoadmapResponse>("mcatRoadmap");
        unlocked = resp.free_practice_unlocked;
        phase = resp.plan?.phase ?? "";
        loading = false;
    }

    onMount(load);
</script>

<div class="mcat-container center">
    <header class="head">
        <h1 class="mcat-title">Extra Practice</h1>
        <p class="mcat-subtitle">Mini-MCAT, section problems, flashcards, and CARS.</p>
    </header>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if !unlocked}
        <div class="locked">
            <div class="lock-badge"><Icon name="lock" size={128} /></div>
            <h2>Finish Today's Path To Unlock</h2>
            <p class="mcat-muted">Extra Practice opens once today's path is done.</p>
            <button
                class="mcat-btn mcat-btn-primary big"
                on:click={() => goto("/mcat/roadmap")}
            >
                Go To Today's Path
            </button>
        </div>
    {:else}
        <button class="mini-card" on:click={() => goto("/mcat/mini")}>
            <div class="mini-name">Mini-MCAT</div>
            <div class="mini-sub">Full exam form across all four sections</div>
            <div class="mini-go">Start →</div>
        </button>

        <section class="grid">
            {#each SECTIONS as code (code)}
                <div
                    class="card"
                    style={`--c:${SECTION_COLOR[code]};--t:${textColor(SECTION_COLOR[code])}`}
                >
                    <div class="card-name">{SECTION_NAMES[code] ?? code}</div>
                    <div class="card-actions">
                        <button
                            class="opt"
                            on:click={() => goto(`/mcat/mini?section=${code}`)}
                        >
                            Problems
                        </button>
                        {#if code !== "cars" && phase !== "final"}
                            <button
                                class="opt"
                                on:click={() =>
                                    goto(`/mcat/flashcards?section=${code}`)}
                            >
                                Flashcards
                            </button>
                        {/if}
                    </div>
                </div>
            {/each}
        </section>
    {/if}
</div>

<style lang="scss">
    .center {
        max-width: 1100px;
        display: flex;
        flex-direction: column;
        align-items: center;
    }
    .head {
        text-align: center;
        margin-bottom: 20px;
    }
    .locked {
        text-align: center;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 14px;
        min-height: 64vh;
        margin: 0 auto;
    }
    .lock-badge {
        width: 200px;
        height: 200px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--mcat-accent);
        background: color-mix(in srgb, var(--mcat-accent) 10%, var(--mcat-surface));
        border: 2px solid color-mix(in srgb, var(--mcat-accent) 22%, var(--mcat-border));
        margin-bottom: 6px;
    }
    .locked h2 {
        margin: 0;
        font-size: 30px;
    }
    .big {
        padding: 14px 22px;
        font-size: 16px;
    }
    .mini-card {
        width: 100%;
        appearance: none;
        border: none;
        text-align: center;
        background: linear-gradient(135deg, #4f46e5, #2563eb);
        color: #ffffff;
        border-radius: 18px;
        padding: 22px;
        cursor: pointer;
        margin-bottom: 18px;
        box-shadow: 0 10px 26px rgba(16, 24, 40, 0.2);
        transition:
            transform 0.1s ease,
            box-shadow 0.12s ease;
    }
    .mini-card:hover {
        background: linear-gradient(135deg, #5b54ea, #3b82f6);
        transform: translateY(-3px);
        box-shadow: 0 16px 32px rgba(16, 24, 40, 0.28);
    }
    .mini-name {
        font-weight: 800;
        font-size: 26px;
    }
    .mini-sub {
        font-size: 16px;
        opacity: 0.92;
        margin-top: 4px;
    }
    .mini-go {
        font-size: 15px;
        font-weight: 700;
        margin-top: 12px;
    }
    .grid {
        width: 100%;
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 16px;
    }
    @media (max-width: 640px) {
        .grid {
            grid-template-columns: 1fr;
        }
    }
    .card {
        background: linear-gradient(
            158deg,
            color-mix(in srgb, var(--c), white 12%),
            var(--c) 46%,
            color-mix(in srgb, var(--c), black 16%)
        );
        color: var(--t);
        border-radius: 18px;
        padding: 22px;
        min-height: 168px;
        display: flex;
        flex-direction: column;
        gap: 14px;
        box-shadow:
            inset 0 1px 0 rgba(255, 255, 255, 0.16),
            0 12px 26px -12px color-mix(in srgb, var(--c) 60%, transparent);
    }
    .card-name {
        font-weight: 800;
        font-size: 21px;
    }
    .card-actions {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: auto;
    }
    .opt {
        border: none;
        border-radius: 10px;
        padding: 10px 16px;
        font-weight: 700;
        font-size: 15px;
        cursor: pointer;
        background: rgba(255, 255, 255, 0.22);
        color: var(--t);
        transition: background 0.12s ease;
    }
    .opt:hover {
        background: rgba(255, 255, 255, 0.34);
    }
</style>
