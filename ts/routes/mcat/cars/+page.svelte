<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

CARS as a debate with the author, not a worksheet: challenge the argument,
switch sides and defend it, then test it against a new condition. No AI grading
yet, so after you commit your reasoning we reveal model answers (a strong
rebuttal and a strong defense) to self-compare against, plus a quick rubric you
rate yourself on. Responses + self-rating are stored (AI-ready) for later.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import Content from "../lib/Content.svelte";
    import Mascot from "../lib/Mascot.svelte";
    import { playStart } from "../lib/sound";
    import type {
        CarsAspect,
        CarsPassage,
        CarsResponse,
        CarsReview,
        CarsRoundResult,
        Profile,
    } from "../lib/types";

    let passage: CarsPassage | null = null;
    let rubric: string[] = [];
    let rubricChecks: boolean[] = [];
    let loading = true;
    let responses: Record<number, string> = {};
    let verdict = "";
    let revealed = false;
    let saving = false;
    let blockId: string | null = null;
    let fromRoadmap = false;

    // AI debate mode: 4 rounds, one aspect each; win 3 of 4 to clear.
    let aiEnabled = false;
    let aspects: CarsAspect[] = [];
    type RoundState = {
        aspect: CarsAspect;
        status: "locked" | "active" | "won" | "lost";
        rivalClaim: string;
        argument: string;
        reply: string;
        note: string;
    };
    let rounds: RoundState[] = [];
    let debStage: "overview" | "round" | "review" = "overview";
    let activeIdx = 0;
    let debateInput = "";
    let busy = false;
    let judged = false;
    let review: CarsReview | null = null;

    $: wonCount = rounds.filter((r) => r.status === "won").length;
    $: decided = rounds.filter((r) => r.status === "won" || r.status === "lost").length;
    $: cleared = wonCount >= 3;
    $: activeRound = rounds[activeIdx];

    function initRounds(): void {
        rounds = aspects.map((a, i) => ({
            aspect: a,
            status: i === 0 ? "active" : "locked",
            rivalClaim: "",
            argument: "",
            reply: "",
            note: "",
        }));
        debStage = "overview";
        activeIdx = 0;
        review = null;
    }

    function statusLabel(r: RoundState, i: number): string {
        if (r.status === "won") {
            return "You won this round";
        }
        if (r.status === "lost") {
            return "Rival won this round";
        }
        if (r.status === "active") {
            return "In progress";
        }
        return i === rounds.findIndex((x) => x.status === "locked")
            ? "Up next"
            : "Locked";
    }

    function enterActive(): void {
        const i = rounds.findIndex((r) => r.status === "active");
        enterRound(i < 0 ? 0 : i);
    }

    async function enterRound(i: number): Promise<void> {
        if (!passage || i < 0 || rounds[i].status === "locked") {
            return;
        }
        activeIdx = i;
        judged = rounds[i].status === "won" || rounds[i].status === "lost";
        debateInput = "";
        debStage = "round";
        if (!rounds[i].rivalClaim) {
            busy = true;
            try {
                const resp = await postJson<{ claim: string | null }>(
                    "mcatCarsRoundOpen",
                    {
                        passage: passage.passage,
                        author_claim: passage.author_claim,
                        aspect_label: rounds[i].aspect.label,
                    },
                );
                rounds[i].rivalClaim =
                    resp.claim ??
                    "My reading of this aspect is the strongest one — prove otherwise.";
                rounds = rounds;
            } finally {
                busy = false;
            }
        }
    }

    async function submitRound(): Promise<void> {
        const msg = debateInput.trim();
        if (!passage || !msg || busy || judged) {
            return;
        }
        busy = true;
        const i = activeIdx;
        rounds[i].argument = msg;
        rounds = rounds;
        try {
            const resp = await postJson<{ result: CarsRoundResult | null }>(
                "mcatCarsRoundJudge",
                {
                    passage: passage.passage,
                    aspect_label: rounds[i].aspect.label,
                    rival_claim: rounds[i].rivalClaim,
                    argument: msg,
                },
            );
            const r = resp.result;
            rounds[i].reply = r?.reply ?? "The author holds their ground.";
            rounds[i].note = r?.note ?? "";
            rounds[i].status = r?.won ? "won" : "lost";
            judged = true;
            debateInput = "";
            rounds = rounds;
        } finally {
            busy = false;
        }
    }

    async function continueRound(): Promise<void> {
        const next = rounds.findIndex((r) => r.status === "locked");
        if (next >= 0) {
            rounds[next].status = "active";
            rounds = rounds;
        }
        if (decided >= rounds.length) {
            await goReview();
        } else {
            debStage = "overview";
        }
    }

    async function goReview(): Promise<void> {
        debStage = "review";
        review = null;
        try {
            const resp = await postJson<{ review: CarsReview | null }>(
                "mcatCarsReview",
                {
                    passage: passage?.passage ?? "",
                    rounds: rounds.map((r) => ({
                        aspect: r.aspect.label,
                        won: r.status === "won",
                        argument: r.argument,
                        note: r.note,
                    })),
                },
            );
            review = resp.review;
        } catch {
            review = null;
        }
    }

    const verdicts = [
        { key: "stronger", label: "Stronger" },
        { key: "weaker", label: "Weaker" },
        { key: "unchanged", label: "Unchanged" },
    ];

    async function load(): Promise<void> {
        loading = true;
        responses = {};
        verdict = "";
        revealed = false;
        const resp = await postJson<CarsResponse>("mcatCars");
        passage = resp.passage;
        rubric = resp.rubric ?? [];
        rubricChecks = rubric.map(() => false);
        aspects = resp.debate_aspects ?? [];
        if (aiEnabled && aspects.length) {
            initRounds();
        }
        loading = false;
    }

    $: lastPromptIsVerdict =
        passage !== null &&
        passage.prompts.length > 0 &&
        /stronger|weaker|unchanged/i.test(passage.prompts[passage.prompts.length - 1]);

    $: allPrompts = passage ? passage.prompts : [];
    $: textPrompts = lastPromptIsVerdict ? allPrompts.slice(0, -1) : allPrompts;
    $: verdictPrompt =
        lastPromptIsVerdict && allPrompts.length > 0
            ? allPrompts[allPrompts.length - 1]
            : "";

    function skillFor(i: number): string {
        return passage?.prompt_skills?.[i] ?? "";
    }

    $: canReveal =
        textPrompts.every((_p, i) => (responses[i] ?? "").trim().length > 0) &&
        (!lastPromptIsVerdict || verdict !== "");

    function reveal(): void {
        if (canReveal) {
            revealed = true;
        }
    }

    async function finish(after: () => void): Promise<void> {
        if (!passage) {
            return;
        }
        saving = true;
        try {
            const missTypes = rubric.filter((_r, i) => !rubricChecks[i]);
            const payloadResponses = aiEnabled
                ? {
                      debate: rounds
                          .map(
                              (r) =>
                                  `[${r.aspect.label}] rival: ${r.rivalClaim} | you: ${r.argument} | result: ${r.status}`,
                          )
                          .join("\n"),
                      won: wonCount,
                      total: rounds.length,
                  }
                : responses;
            await postJson("mcatSubmitCars", {
                note_id: passage.note_id,
                responses: payloadResponses,
                verdict: verdict || null,
                miss_types: missTypes,
            });
            if (fromRoadmap && blockId) {
                await postJson("mcatCompleteBlock", { block_id: blockId });
            }
            after();
        } finally {
            saving = false;
        }
    }

    onMount(async () => {
        blockId = $page.url.searchParams.get("block");
        fromRoadmap = $page.url.searchParams.get("from") === "roadmap";
        try {
            const p = await postJson<{ profile: Profile }>("mcatGetProfile");
            aiEnabled = p.profile.ai_enabled ?? false;
        } catch {
            aiEnabled = false;
        }
        load();
        playStart("cars");
    });
</script>

<div class="mcat-container">
    <header class="mcat-header">
        <div>
            <h1 class="mcat-title">CARS Author Duel</h1>
            <p class="mcat-subtitle">
                Debate the author. Challenge it, defend it, then stress-test it.
            </p>
        </div>
    </header>

    {#if loading}
        <div class="mcat-card">Loading a passage…</div>
    {:else if !passage}
        <div class="mcat-card">
            <p>
                No CARS passage available yet. Install starter content from the
                dashboard.
            </p>
            <button class="mcat-btn" on:click={() => goto("/mcat/dashboard")}>
                Go to dashboard
            </button>
        </div>
    {:else}
        <div class="mcat-card passage">
            <div class="passage-label mcat-muted">Passage</div>
            <div class="passage-text"><Content text={passage.passage} /></div>
        </div>

        {#if aiEnabled}
            {#if debStage === "review"}
                <div class="review-wrap">
                    <Mascot size={82} mood={cleared ? "happy" : "neutral"} />
                    <div class="review-score">Won {wonCount} of {rounds.length}</div>
                    <div class="review-sub mcat-muted">
                        {cleared ? "Passage cleared" : "Not cleared — win 3 of 4"}
                    </div>
                    {#if review}
                        {#if review.did_well.length}
                            <div class="mcat-card slip did">
                                <div class="slip-title">Did well</div>
                                {#each review.did_well as d (d)}
                                    <div class="slip-item">{d}</div>
                                {/each}
                            </div>
                        {/if}
                        {#if review.work_on.length}
                            <div class="mcat-card slip work">
                                <div class="slip-title">Work on</div>
                                {#each review.work_on as w (w)}
                                    <div class="slip-item">{w}</div>
                                {/each}
                            </div>
                        {/if}
                    {:else}
                        <p class="mcat-muted">Your coach is reviewing the debate…</p>
                    {/if}
                    <div class="row center">
                        {#if fromRoadmap}
                            <button
                                class="mcat-btn mcat-btn-primary"
                                disabled={saving}
                                on:click={() => finish(() => goto("/mcat/roadmap"))}
                            >
                                {saving ? "Saving…" : "Finish & back to roadmap"}
                            </button>
                        {:else}
                            <button
                                class="mcat-btn"
                                disabled={saving}
                                on:click={() => finish(load)}
                            >
                                Next passage
                            </button>
                            <button
                                class="mcat-btn mcat-btn-primary"
                                disabled={saving}
                                on:click={() => finish(() => goto("/mcat/dashboard"))}
                            >
                                Done
                            </button>
                        {/if}
                    </div>
                </div>
            {:else if debStage === "round" && activeRound}
                <div class="rounds-bar">
                    {#each rounds as r, i (r.aspect.key)}
                        <span
                            class="rseg {r.status}"
                            class:cur={i === activeIdx}
                        ></span>
                    {/each}
                </div>
                <div class="round-head">
                    <span class="round-aspect">
                        Arguing: {activeRound.aspect.label}
                    </span>
                    <span class="round-count mcat-muted">
                        Round {activeIdx + 1} of {rounds.length}
                    </span>
                </div>

                <div class="chat">
                    {#if activeRound.rivalClaim}
                        <div class="msg rival">
                            <div class="avatar">
                                <Mascot size={40} color="#e2492f" mood="neutral" />
                            </div>
                            <div class="bubble rival-bubble">
                                <div class="who rival-who">Rival</div>
                                <p>{activeRound.rivalClaim}</p>
                            </div>
                        </div>
                    {:else if busy}
                        <div class="msg rival">
                            <div class="avatar">
                                <Mascot size={40} color="#e2492f" mood="neutral" />
                            </div>
                            <div class="bubble rival-bubble">
                                <p class="mcat-muted">…</p>
                            </div>
                        </div>
                    {/if}

                    {#if activeRound.argument}
                        <div class="msg you">
                            <div class="bubble you-bubble">
                                <div class="who you-who">You</div>
                                <p>{activeRound.argument}</p>
                            </div>
                            <div class="avatar"><Mascot size={40} /></div>
                        </div>
                    {/if}

                    {#if judged && activeRound.reply}
                        <div class="msg rival">
                            <div class="avatar">
                                <Mascot size={40} color="#e2492f" mood="neutral" />
                            </div>
                            <div class="bubble rival-bubble">
                                <div class="who rival-who">Rival</div>
                                <p>{activeRound.reply}</p>
                            </div>
                        </div>
                    {/if}
                </div>

                {#if judged}
                    <div class="verdict-line {activeRound.status}">
                        {activeRound.status === "won"
                            ? "You won this round"
                            : "Rival won this round"}
                        {#if activeRound.note}
                            <span class="verdict-note">· {activeRound.note}</span>
                        {/if}
                    </div>
                    <button class="mcat-btn mcat-btn-primary" on:click={continueRound}>
                        {decided >= rounds.length ? "See results" : "Continue"}
                    </button>
                {:else}
                    <div class="compose">
                        <textarea
                            rows="3"
                            bind:value={debateInput}
                            placeholder="Rebut the rival in your own words…"
                            disabled={busy}
                        ></textarea>
                        <button
                            class="mcat-btn mcat-btn-primary"
                            disabled={busy || debateInput.trim().length < 3}
                            on:click={submitRound}
                        >
                            {busy ? "…" : "Send"}
                        </button>
                    </div>
                {/if}
                <button class="link-btn" on:click={() => (debStage = "overview")}>
                    ← All rounds
                </button>
            {:else}
                <div class="mcat-card overview">
                    <div class="ov-title">Debate this passage</div>
                    <div class="ov-sub mcat-muted">
                        {rounds.length} rounds · one aspect each
                    </div>
                    <div class="rounds-list">
                        {#each rounds as r, i (r.aspect.key)}
                            <button
                                class="round-row {r.status}"
                                disabled={r.status === "locked"}
                                on:click={() => enterRound(i)}
                            >
                                <span class="rr-dot {r.status}"></span>
                                <span class="rr-name">{r.aspect.label}</span>
                                <span class="rr-status">{statusLabel(r, i)}</span>
                            </button>
                        {/each}
                    </div>
                    <div class="ov-foot">Win 3 of 4 to clear the passage</div>
                </div>
                <button class="mcat-btn mcat-btn-primary" on:click={enterActive}>
                    {decided > 0 ? "Continue" : "Start debate"}
                </button>
            {/if}
        {:else if !revealed}
            <div class="prompts">
                {#each textPrompts as prompt, i (i)}
                    <div class="mcat-card prompt">
                        <div class="prompt-head">
                            <label class="prompt-q" for={`prompt-${i}`}>{prompt}</label>
                            {#if skillFor(i)}<span class="skill-chip">
                                    {skillFor(i)}
                                </span>{/if}
                        </div>
                        <textarea
                            id={`prompt-${i}`}
                            rows="3"
                            bind:value={responses[i]}
                        ></textarea>
                    </div>
                {/each}

                {#if lastPromptIsVerdict}
                    <div class="mcat-card prompt">
                        <div class="prompt-head">
                            <div class="prompt-q">{verdictPrompt}</div>
                            {#if skillFor(textPrompts.length)}<span class="skill-chip">
                                    {skillFor(textPrompts.length)}
                                </span>{/if}
                        </div>
                        <div class="verdicts">
                            {#each verdicts as v (v.key)}
                                <button
                                    type="button"
                                    class="mcat-btn"
                                    class:selected={verdict === v.key}
                                    on:click={() => (verdict = v.key)}
                                >
                                    {v.label}
                                </button>
                            {/each}
                        </div>
                    </div>
                {/if}

                <button
                    class="mcat-btn mcat-btn-primary"
                    disabled={!canReveal}
                    on:click={reveal}
                >
                    Commit & compare answers
                </button>
            </div>
        {:else}
            <div class="mcat-card reveal">
                <div class="feedback-title">The author's core claim</div>
                <p>{passage.author_claim}</p>
                <p class="mcat-muted skill">
                    CARS skill: {passage.skill_type.replace(/_/g, " ")}
                </p>

                {#if passage.strong_rebuttal || passage.strong_defense}
                    <div class="models">
                        {#if passage.strong_rebuttal}
                            <div class="model">
                                <div class="model-title">A strong challenge</div>
                                <p>{passage.strong_rebuttal}</p>
                            </div>
                        {/if}
                        {#if passage.strong_defense}
                            <div class="model">
                                <div class="model-title">A strong defense</div>
                                <p>{passage.strong_defense}</p>
                            </div>
                        {/if}
                    </div>
                {/if}
            </div>

            {#if rubric.length}
                <div class="mcat-card rubric">
                    <div class="feedback-title">Rate your reasoning</div>
                    <p class="mcat-muted">
                        Check what you actually did — the rest is logged as a focus
                        area.
                    </p>
                    {#each rubric as item, i (i)}
                        <label class="rubric-item">
                            <input type="checkbox" bind:checked={rubricChecks[i]} />
                            <span>{item}</span>
                        </label>
                    {/each}
                </div>
            {/if}

            <div class="row">
                {#if fromRoadmap}
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={saving}
                        on:click={() => finish(() => goto("/mcat/roadmap"))}
                    >
                        {saving ? "Saving…" : "Save & back to roadmap"}
                    </button>
                {:else}
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={saving}
                        on:click={() => finish(() => goto("/mcat/dashboard"))}
                    >
                        {saving ? "Saving…" : "Save & finish"}
                    </button>
                    <button
                        class="mcat-btn"
                        disabled={saving}
                        on:click={() => finish(load)}
                    >
                        Save & another passage
                    </button>
                {/if}
            </div>
        {/if}
    {/if}
</div>

<style lang="scss">
    .passage {
        margin-bottom: 18px;
    }
    .passage-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin-bottom: 8px;
    }
    .passage-text {
        margin: 0;
        font-size: 18px;
        line-height: 1.6;
    }
    .prompts {
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .prompt-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 8px;
    }
    .prompt-q {
        font-weight: 600;
    }
    .skill-chip {
        flex: 0 0 auto;
        font-size: 12px;
        font-weight: 600;
        color: var(--mcat-accent);
        background: color-mix(in srgb, var(--mcat-accent) 12%, transparent);
        border: 1px solid color-mix(in srgb, var(--mcat-accent) 30%, transparent);
        border-radius: 999px;
        padding: 3px 10px;
        white-space: nowrap;
    }
    textarea {
        width: 100%;
        border-radius: 10px;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-bg);
        color: var(--mcat-text);
        padding: 10px 12px;
        font: inherit;
        font-size: 15px;
        resize: vertical;
    }
    .verdicts {
        display: flex;
        gap: 8px;
    }
    .selected {
        border-color: var(--mcat-accent);
        color: var(--mcat-accent);
    }
    .feedback-title {
        font-weight: 700;
        font-size: 18px;
        margin-bottom: 6px;
    }
    .skill {
        font-size: 13px;
    }
    .models {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 14px;
        margin-top: 14px;
    }
    @media (max-width: 720px) {
        .models {
            grid-template-columns: 1fr;
        }
    }
    .model {
        background: var(--mcat-bg);
        border: 1px solid var(--mcat-border);
        border-radius: 12px;
        padding: 14px 16px;
    }
    .model-title {
        font-weight: 700;
        font-size: 14px;
        margin-bottom: 6px;
        color: var(--mcat-accent);
    }
    .model p {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
    }
    .rubric {
        margin-top: 16px;
        display: flex;
        flex-direction: column;
        gap: 4px;
    }
    .rubric-item {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 8px 0;
        font-size: 15px;
        cursor: pointer;
    }
    .rubric-item input {
        margin-top: 3px;
        width: 17px;
        height: 17px;
        flex: 0 0 auto;
    }
    .row {
        display: flex;
        gap: 10px;
        margin-top: 16px;
        flex-wrap: wrap;
    }
    .row.center {
        justify-content: center;
    }
    /* Round-based debate */
    .rounds-bar {
        display: flex;
        gap: 6px;
        margin-bottom: 14px;
    }
    .rseg {
        flex: 1;
        height: 8px;
        border-radius: 999px;
        background: var(--mcat-track);
    }
    .rseg.won {
        background: var(--mcat-green);
    }
    .rseg.lost {
        background: var(--mcat-red);
    }
    .rseg.active {
        background: var(--mcat-accent);
    }
    .rseg.cur {
        box-shadow: 0 0 0 2px color-mix(in srgb, var(--mcat-accent) 40%, transparent);
    }
    .round-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 12px;
    }
    .round-aspect {
        font-size: 18px;
        font-weight: 800;
        color: var(--mcat-text);
    }
    .round-count {
        font-size: 13px;
        font-weight: 700;
    }
    .chat {
        display: flex;
        flex-direction: column;
        gap: 14px;
        margin-bottom: 14px;
    }
    .msg {
        display: flex;
        align-items: flex-end;
        gap: 10px;
        max-width: 92%;
    }
    .msg.you {
        align-self: flex-end;
    }
    .msg.rival {
        align-self: flex-start;
    }
    .avatar {
        flex: 0 0 auto;
    }
    .bubble {
        border-radius: 16px;
        padding: 12px 15px;
    }
    .bubble p {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
    }
    .rival-bubble {
        background: color-mix(in srgb, #e2492f 12%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, #e2492f 24%, var(--mcat-border));
        border-bottom-left-radius: 4px;
    }
    .you-bubble {
        background: var(--mcat-accent);
        color: #fff;
        border-bottom-right-radius: 4px;
    }
    .who {
        font-size: 11px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        margin-bottom: 4px;
    }
    .rival-who {
        color: #e2492f;
    }
    .you-who {
        color: rgba(255, 255, 255, 0.85);
    }
    .verdict-line {
        font-size: 15px;
        font-weight: 800;
        margin-bottom: 12px;
    }
    .verdict-line.won {
        color: var(--mcat-green);
    }
    .verdict-line.lost {
        color: var(--mcat-red);
    }
    .verdict-note {
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .compose {
        display: flex;
        gap: 10px;
        align-items: flex-end;
    }
    .compose textarea {
        flex: 1;
    }
    .link-btn {
        appearance: none;
        border: none;
        background: none;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
        margin-top: 12px;
        padding: 0;
    }
    /* Overview */
    .overview {
        margin-bottom: 14px;
    }
    .ov-title {
        font-size: 20px;
        font-weight: 800;
    }
    .ov-sub {
        font-size: 14px;
        margin-top: 2px;
    }
    .rounds-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin: 14px 0;
    }
    .round-row {
        appearance: none;
        cursor: pointer;
        display: flex;
        align-items: center;
        gap: 12px;
        width: 100%;
        text-align: left;
        border: 1.5px solid var(--mcat-border);
        border-radius: 12px;
        background: var(--mcat-surface);
        padding: 14px 16px;
        color: var(--mcat-text);
    }
    .round-row.active {
        border-color: var(--mcat-accent);
        box-shadow: 0 0 0 1px var(--mcat-accent);
    }
    .round-row:disabled {
        opacity: 0.55;
        cursor: default;
    }
    .rr-dot {
        flex: 0 0 auto;
        width: 26px;
        height: 26px;
        border-radius: 50%;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
    }
    .rr-dot.won {
        background: color-mix(in srgb, var(--mcat-green) 22%, var(--mcat-surface));
        border-color: var(--mcat-green);
    }
    .rr-dot.lost {
        background: color-mix(in srgb, var(--mcat-red) 22%, var(--mcat-surface));
        border-color: var(--mcat-red);
    }
    .rr-dot.active {
        background: color-mix(in srgb, var(--mcat-accent) 22%, var(--mcat-surface));
        border-color: var(--mcat-accent);
    }
    .rr-name {
        font-weight: 800;
        font-size: 16px;
    }
    .rr-status {
        margin-left: auto;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
    }
    .round-row.active .rr-status {
        color: var(--mcat-accent);
    }
    .round-row.won .rr-status {
        color: var(--mcat-green);
    }
    .ov-foot {
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
        text-align: center;
    }
    /* Review */
    .review-wrap {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        text-align: center;
    }
    .review-score {
        font-size: 24px;
        font-weight: 800;
        color: var(--mcat-text);
    }
    .review-sub {
        font-size: 15px;
        margin-top: -6px;
    }
    .slip {
        width: 100%;
        text-align: center;
    }
    .slip.did {
        border-left: 4px solid var(--mcat-green);
    }
    .slip.work {
        border-left: 4px solid var(--mcat-amber);
    }
    .slip-title {
        font-size: 14px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin-bottom: 12px;
    }
    .slip.did .slip-title {
        color: var(--mcat-green);
    }
    .slip.work .slip-title {
        color: var(--mcat-amber);
    }
    .slip-item {
        font-size: 18px;
        line-height: 1.55;
        padding: 12px 0;
        color: var(--mcat-text);
    }
    .slip-item + .slip-item {
        border-top: 1px solid var(--mcat-border);
    }
</style>
