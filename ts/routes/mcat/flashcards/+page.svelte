<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Spaced Review: FSRS flashcards. Reveal the answer, then rate recall
(Again / Hard / Good / Easy) — the rating schedules the card and feeds the
Memory Recall score.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import { playStart } from "../lib/sound";
    import { SECTION_NAMES } from "../lib/types";

    interface Flashcard {
        note_id: number;
        card_id: number | null;
        front: string;
        back: string;
        section: string;
        topic_ids: string[];
    }

    const RATINGS = [
        { key: "again", label: "Again", color: "var(--mcat-red)" },
        { key: "hard", label: "Hard", color: "var(--mcat-amber)" },
        { key: "good", label: "Good", color: "var(--mcat-green)" },
        { key: "easy", label: "Easy", color: "var(--mcat-blue)" },
    ];

    let cards: Flashcard[] = [];
    let idx = 0;
    let revealed = false;
    let loading = true;
    let busy = false;
    let section: string | null = null;
    let blockId: string | null = null;
    let fromRoadmap = false;
    let count = 15;

    async function load(): Promise<void> {
        loading = true;
        const resp = await postJson<{ cards: Flashcard[] }>("mcatFlashcards", {
            section,
            count,
        });
        cards = resp.cards;
        idx = 0;
        revealed = false;
        loading = false;
    }

    async function finishDeck(): Promise<void> {
        if (fromRoadmap && blockId) {
            await postJson("mcatCompleteBlock", { block_id: blockId });
            goto("/mcat/roadmap");
        } else {
            idx = cards.length;
        }
    }

    async function grade(rating: string): Promise<void> {
        if (busy) {
            return;
        }
        busy = true;
        try {
            const c = cards[idx];
            if (c?.card_id) {
                await postJson("mcatGradeCard", { card_id: c.card_id, rating });
            }
            if (idx + 1 < cards.length) {
                idx += 1;
                revealed = false;
            } else {
                await finishDeck();
            }
        } finally {
            busy = false;
        }
    }

    onMount(() => {
        section = $page.url.searchParams.get("section");
        blockId = $page.url.searchParams.get("block");
        fromRoadmap = $page.url.searchParams.get("from") === "roadmap";
        const c = Number($page.url.searchParams.get("count"));
        if (c > 0) {
            count = c;
        }
        load();
        playStart("memory");
    });

    $: card = cards[idx];
</script>

<div class="mcat-container study">
    {#if loading}
        <div class="mcat-card">Loading flashcards…</div>
    {:else if cards.length === 0}
        <div class="mcat-card">
            <p>No flashcards available for this section yet.</p>
            <button class="mcat-btn" on:click={() => goto("/mcat/extra")}>
                Back to Extra Practice
            </button>
        </div>
    {:else if idx >= cards.length}
        <div class="mcat-card done">
            <h2>Deck Complete</h2>
            <p class="mcat-muted">You reviewed {cards.length} cards.</p>
            <div class="row">
                <button class="mcat-btn mcat-btn-primary" on:click={load}>
                    Review Again
                </button>
                <button class="mcat-btn" on:click={() => goto("/mcat/extra")}>
                    Extra Practice
                </button>
            </div>
        </div>
    {:else}
        <div class="study-head">
            <span class="tag">
                <span class="dot green"></span>
                Spaced Review
            </span>
            <span class="counter">Card {idx + 1} Of {cards.length}</span>
        </div>

        <div class="mcat-card flashcard">
            {#if section}<div class="fc-section">
                    {SECTION_NAMES[section] ?? section}
                </div>{/if}
            <div class="front">{card.front}</div>
            {#if revealed}
                <hr />
                <div class="back">{card.back}</div>
            {/if}
        </div>

        {#if !revealed}
            <button
                class="mcat-btn mcat-btn-primary reveal"
                on:click={() => (revealed = true)}
            >
                Reveal Answer
            </button>
        {:else}
            <div class="recall-label">How Easily Did You Recall This?</div>
            <div class="ratings">
                {#each RATINGS as r (r.key)}
                    <button
                        class="rate"
                        style={`--c:${r.color}`}
                        disabled={busy}
                        on:click={() => grade(r.key)}
                    >
                        {r.label}
                    </button>
                {/each}
            </div>
        {/if}
    {/if}
</div>

<style lang="scss">
    .study {
        max-width: 720px;
    }
    .study-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
    }
    .tag {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        font-size: 15px;
        font-weight: 700;
    }
    .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
    }
    .dot.green {
        background: var(--mcat-green);
    }
    .counter {
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .flashcard {
        min-height: 260px;
        display: flex;
        flex-direction: column;
        gap: 18px;
        text-align: center;
        align-items: center;
        justify-content: center;
        padding: 32px 28px;
    }
    .fc-section {
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--mcat-muted);
    }
    .front {
        font-size: 23px;
        font-weight: 800;
        line-height: 1.35;
    }
    hr {
        border: none;
        border-top: 1px solid var(--mcat-border);
        width: 100%;
        margin: 0;
    }
    .back {
        font-size: 18px;
        line-height: 1.6;
        color: var(--mcat-text);
    }
    .reveal {
        width: 100%;
        margin-top: 16px;
        padding: 14px;
        font-size: 16px;
    }
    .recall-label {
        text-align: center;
        font-size: 15px;
        font-weight: 600;
        color: var(--mcat-muted);
        margin: 18px 0 12px;
    }
    .ratings {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 10px;
    }
    .rate {
        appearance: none;
        cursor: pointer;
        border: 1px solid color-mix(in srgb, var(--c) 35%, var(--mcat-border));
        background: color-mix(in srgb, var(--c) 12%, var(--mcat-surface));
        color: var(--c);
        border-radius: 12px;
        padding: 16px 8px;
        font-size: 16px;
        font-weight: 700;
        transition:
            background 0.12s ease,
            transform 0.08s ease;
    }
    .rate:hover:not(:disabled) {
        background: color-mix(in srgb, var(--c) 20%, var(--mcat-surface));
    }
    .rate:active {
        transform: translateY(1px);
    }
    .done {
        text-align: center;
    }
    .done h2 {
        margin-top: 0;
    }
    .row {
        display: flex;
        gap: 10px;
        justify-content: center;
        flex-wrap: wrap;
    }
</style>
