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
    import DailyDiagnostic from "../lib/DailyDiagnostic.svelte";
    import Icon from "../lib/Icon.svelte";
    import { SECTION_NAMES } from "../lib/types";
    import type { DashboardData, Profile, RoadmapResponse, Scores } from "../lib/types";

    const SECTIONS = ["bb", "cp", "ps", "cars"];

    let unlocked = false;
    let loading = true;
    let phase = "";
    let aiEnabled = false;
    let lastDiagDate: string | null = null;
    let scores: Scores | null = null;

    // Lightweight "study this next" recommendation, straight from the scores:
    // the weakest section, and whether flashcards or problems are more needed.
    type Measure = "memory" | "performance";
    function pt(code: string, measure: Measure): number | null {
        const sec = scores?.sections[code];
        if (!sec) {
            return null;
        }
        const b = measure === "memory" ? sec.memory : sec.performance;
        return b && !b.abstained && b.point != null ? b.point : null;
    }
    function actionFor(code: string): "flashcards" | "problems" {
        if (code === "cars") {
            return "problems";
        }
        const m = pt(code, "memory");
        const p = pt(code, "performance");
        if (m != null && p != null && m < p - 8) {
            return "flashcards";
        }
        if (m != null && p == null) {
            return "flashcards";
        }
        return "problems";
    }
    function weakness(code: string): number {
        const p = pt(code, "performance");
        return p == null ? 0.6 : 1 - p / 100;
    }
    $: weakestCode = scores
        ? SECTIONS.reduce((a, b) => (weakness(b) > weakness(a) ? b : a))
        : null;

    function localDay(d: Date): string {
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }
    // Available once the stored date isn't today. mcatRoadmap pulls from the
    // cloud first, so this reflects a diagnostic taken on the other device today.
    $: diagAvailable = lastDiagDate !== localDay(new Date());

    async function load(): Promise<void> {
        loading = true;
        const resp = await postJson<RoadmapResponse>("mcatRoadmap");
        unlocked = resp.free_practice_unlocked;
        phase = resp.plan?.phase ?? "";
        try {
            const p = await postJson<{ profile: Profile }>("mcatGetProfile");
            aiEnabled = p.profile.ai_enabled ?? false;
            lastDiagDate = p.profile.last_diagnostic_date ?? null;
        } catch {
            aiEnabled = false;
        }
        if (unlocked) {
            try {
                const d = await postJson<DashboardData>("mcatDashboard");
                scores = d.scores;
            } catch {
                scores = null;
            }
        }
        loading = false;
    }

    // CARS: an interactive AI debate when AI is on, else the MCQ set.
    function carsDest(): string {
        return aiEnabled ? "/mcat/cars" : "/mcat/mini?section=cars";
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
            <div class="lock-badge">
                <span class="seal"></span>
                <Icon name="lock" size={128} />
            </div>
            <h2>Finish Today's Path To Unlock</h2>
            <p class="mcat-muted">Extra Practice opens once today's path is done.</p>
            <button
                class="mcat-btn mcat-btn-primary big"
                on:click={() => goto("/mcat/roadmap")}
            >
                Go To Today's Path
            </button>
            <DailyDiagnostic available={diagAvailable} />
        </div>
    {:else}
        <button class="mini-card" on:click={() => goto("/mcat/mini")}>
            <div class="mini-name">Mini-MCAT</div>
            <div class="mini-sub">Full exam form across all four sections</div>
            <div class="mini-go">Start →</div>
        </button>

        <section class="grid">
            {#each SECTIONS as code, i (code)}
                <div
                    class="card"
                    class:weakest={code === weakestCode}
                    style={`--c:${SECTION_COLOR[code]};--t:${textColor(SECTION_COLOR[code])};--i:${i}`}
                >
                    <div class="card-top">
                        <div class="card-name">{SECTION_NAMES[code] ?? code}</div>
                        {#if code === weakestCode}
                            <span class="weak-badge">Weakest</span>
                        {/if}
                    </div>
                    <div class="card-actions">
                        <button
                            class="opt"
                            class:rec={actionFor(code) === "problems"}
                            on:click={() =>
                                goto(
                                    code === "cars"
                                        ? carsDest()
                                        : `/mcat/mini?section=${code}`,
                                )}
                        >
                            {code === "cars" && aiEnabled ? "Debate" : "Problems"}
                            {#if actionFor(code) === "problems"}
                                <span class="rec-tag">Recommended</span>
                            {/if}
                        </button>
                        {#if code !== "cars" && phase !== "final"}
                            <button
                                class="opt"
                                class:rec={actionFor(code) === "flashcards"}
                                on:click={() =>
                                    goto(`/mcat/flashcards?section=${code}`)}
                            >
                                Flashcards
                                {#if actionFor(code) === "flashcards"}
                                    <span class="rec-tag">Recommended</span>
                                {/if}
                            </button>
                        {/if}
                    </div>
                </div>
            {/each}
        </section>

        <DailyDiagnostic available={diagAvailable} />
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
        position: relative;
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
        /* Drops in and clicks shut, then a periodic "locked" tug. */
        animation:
            lockdrop 0.7s cubic-bezier(0.2, 1.05, 0.35, 1) both,
            lockjiggle 3.4s ease-in-out 1.2s infinite;
    }
    .seal {
        position: absolute;
        inset: -8px;
        border-radius: 50%;
        border: 2px solid color-mix(in srgb, var(--mcat-accent) 45%, transparent);
        pointer-events: none;
        animation: seal 2.6s ease-out infinite;
    }
    @keyframes lockdrop {
        0% {
            opacity: 0;
            transform: translateY(-38px) scale(0.7);
        }
        62% {
            opacity: 1;
            transform: translateY(5px) scale(1.04);
        }
        100% {
            transform: translateY(0) scale(1);
        }
    }
    @keyframes lockjiggle {
        0%,
        88%,
        100% {
            transform: rotate(0);
        }
        90% {
            transform: rotate(-5deg);
        }
        93% {
            transform: rotate(5deg);
        }
        96% {
            transform: rotate(-3deg);
        }
        98% {
            transform: rotate(2deg);
        }
    }
    @keyframes seal {
        0% {
            transform: scale(0.9);
            opacity: 0.8;
        }
        70% {
            opacity: 0;
        }
        100% {
            transform: scale(1.28);
            opacity: 0;
        }
    }
    .locked h2 {
        margin: 0;
        font-size: 30px;
    }
    /* Text + button rise in under the lock. */
    .locked h2,
    .locked p,
    .locked .big {
        animation: rise 0.5s cubic-bezier(0.2, 0.8, 0.3, 1) both;
    }
    .locked h2 {
        animation-delay: 0.5s;
    }
    .locked p {
        animation-delay: 0.58s;
    }
    .locked .big {
        animation-delay: 0.66s;
    }
    @keyframes rise {
        from {
            opacity: 0;
            transform: translateY(12px);
        }
        to {
            opacity: 1;
            transform: none;
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .lock-badge,
        .seal,
        .locked h2,
        .locked p,
        .locked .big,
        .mini-card,
        .grid .card {
            animation: none;
        }
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
        animation: rise 0.5s cubic-bezier(0.2, 0.8, 0.3, 1) both;
        animation-delay: 0.05s;
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
        animation: rise 0.5s cubic-bezier(0.2, 0.8, 0.3, 1) both;
        animation-delay: calc(var(--i, 0) * 70ms + 0.12s);
    }
    .card.weakest {
        box-shadow:
            inset 0 1px 0 rgba(255, 255, 255, 0.16),
            0 0 0 2px rgba(255, 255, 255, 0.55),
            0 12px 26px -12px color-mix(in srgb, var(--c) 60%, transparent);
    }
    .card-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
    }
    .card-name {
        font-weight: 800;
        font-size: 21px;
    }
    .weak-badge {
        font-size: 11px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        background: rgba(255, 255, 255, 0.28);
        color: var(--t);
        border-radius: 999px;
        padding: 3px 10px;
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
    .opt.rec {
        background: rgba(255, 255, 255, 0.92);
        color: #1f2340;
    }
    .rec-tag {
        display: inline-block;
        margin-left: 8px;
        font-size: 10px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.03em;
        color: #7c3aed;
    }
</style>
