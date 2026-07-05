<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Today's Path: a winding vertical path of circular activity nodes. Nodes are
colored by activity type (Spaced Review / Performance Set / Section Practice);
done = check, current = dashed "Up Next" ring, later = locked. Finishes on a
streak node. Auto-scrolls to your current node.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount, tick } from "svelte";

    import { postJson } from "../lib/api";
    import { activityMeta, blockRoute } from "../lib/blocks";
    import Icon from "../lib/Icon.svelte";
    import { playStreak } from "../lib/sound";
    import { SECTION_NAMES } from "../lib/types";
    import type {
        Profile,
        RoadmapBlock,
        RoadmapResponse,
        Roadmap,
        Streak,
        WhyThis,
    } from "../lib/types";

    const ROW = 196;

    let plan: Roadmap | null = null;
    let streak: Streak | null = null;
    let freePracticeUnlocked = false;
    let why: WhyThis | null = null;
    let loading = true;
    let pathEl: HTMLDivElement | undefined;

    let isDev = false;
    let aiEnabled = false;
    let wasUnlocked: boolean | null = null;
    let devBlock: RoadmapBlock | null = null;
    let devTotal = 0;
    let devCorrect = 0;
    let devBusy = false;

    function apply(resp: RoadmapResponse): void {
        // Celebrate only on the transition to "done", not when re-opening a
        // roadmap that was already finished earlier.
        if (wasUnlocked === false && resp.free_practice_unlocked) {
            playStreak();
        }
        wasUnlocked = resp.free_practice_unlocked;
        plan = resp.plan;
        streak = resp.streak;
        freePracticeUnlocked = resp.free_practice_unlocked;
        why = resp.why ?? null;
        isDev = resp.is_dev;
    }

    // Per-node completed score → color + a short qualifier ("best today"/"shaky").
    function scoreFrac(b: RoadmapBlock): number {
        return b.score && b.score.total ? b.score.correct / b.score.total : 0;
    }
    function scoreColor(b: RoadmapBlock): string {
        const f = scoreFrac(b);
        if (f < 0.7) {
            return "var(--mcat-red)";
        }
        if (f < 0.85) {
            return "var(--mcat-amber)";
        }
        return "var(--mcat-green)";
    }
    function bestScored(blocks: RoadmapBlock[]): string | null {
        let best: { id: string; f: number } | null = null;
        for (const b of blocks) {
            if (b.completed && b.score && b.score.total) {
                const f = b.score.correct / b.score.total;
                if (!best || f > best.f) {
                    best = { id: b.id, f };
                }
            }
        }
        return best && best.f >= 0.8 ? best.id : null;
    }
    $: bestBlockId = plan ? bestScored(plan.blocks) : null;
    function scoreSuffix(b: RoadmapBlock): string {
        const f = scoreFrac(b);
        if (b.id === bestBlockId && f >= 0.8) {
            return " · best today";
        }
        if (f < 0.7) {
            return " · shaky";
        }
        return "";
    }
    function whyTone(p: number): string {
        if (p < 70) {
            return "var(--mcat-red)";
        }
        if (p < 85) {
            return "var(--mcat-amber)";
        }
        return "var(--mcat-green)";
    }

    async function load(): Promise<void> {
        loading = true;
        apply(await postJson<RoadmapResponse>("mcatRoadmap"));
        try {
            const p = await postJson<{ profile: Profile }>("mcatGetProfile");
            aiEnabled = p.profile.ai_enabled ?? false;
        } catch {
            aiEnabled = false;
        }
        loading = false;
        await scrollActive();
    }

    $: firstIncomplete = plan ? plan.blocks.findIndex((b) => !b.completed) : -1;
    $: allRequiredDone = freePracticeUnlocked;
    $: doneCount = plan ? plan.blocks.filter((b) => b.completed).length : 0;
    $: statuses = computeStatuses(plan, firstIncomplete);

    function computeStatuses(
        p: Roadmap | null,
        fi: number,
    ): ("done" | "active" | "locked")[] {
        if (!p) {
            return [];
        }
        return p.blocks.map((b, i) => {
            if (b.completed) {
                return "done";
            }
            if (i === fi) {
                return "active";
            }
            return "locked";
        });
    }

    function posX(i: number): number {
        return i % 2 === 0 ? 22 : 78;
    }

    // Node centres (viewBox x 0–100, y in px) for the SVG connectors + the
    // trailing finish node.
    $: nodes = plan
        ? [
              ...plan.blocks.map((_b, i) => ({ cx: posX(i), cy: i * ROW + ROW / 2 })),
              { cx: 50, cy: plan.blocks.length * ROW + ROW / 2 },
          ]
        : [];
    $: connectors = nodes.slice(0, -1).map((n, i) => ({
        key: i,
        x1: n.cx,
        y1: n.cy,
        x2: nodes[i + 1].cx,
        y2: nodes[i + 1].cy,
        solid: !!plan && !!plan.blocks[i]?.completed,
    }));
    $: totalH = nodes.length ? nodes[nodes.length - 1].cy + ROW / 2 : 0;

    // A pulse that travels along the completed connector into the active node
    // (the little dot in the mockup). Only when there's a done -> active hop.
    $: travel =
        plan && firstIncomplete > 0 && firstIncomplete < plan.blocks.length
            ? {
                  sx: posX(firstIncomplete - 1),
                  sy: (firstIncomplete - 1) * ROW + ROW / 2,
                  ex: posX(firstIncomplete),
                  ey: firstIncomplete * ROW + ROW / 2,
              }
            : null;

    function start(block: RoadmapBlock, i: number): void {
        if (statuses[i] === "locked") {
            return;
        }
        goto(blockRoute(block, aiEnabled));
    }

    function blockSub(block: RoadmapBlock): string {
        if (block.section) {
            return SECTION_NAMES[block.section] ?? block.section;
        }
        return activityMeta(block).label;
    }

    async function scrollActive(): Promise<void> {
        await tick();
        const el = pathEl?.querySelector<HTMLElement>(".node.active");
        if (!el) {
            return;
        }
        // Only scroll when the current node is below the comfortable viewport, so
        // an early node doesn't tuck the page header under the sticky nav.
        const r = el.getBoundingClientRect();
        if (r.top > window.innerHeight * 0.72 || r.bottom < 80) {
            el.scrollIntoView({ behavior: "smooth", block: "center" });
        }
    }

    function blockCount(block: RoadmapBlock): number {
        const c = Number(block.meta?.count);
        return Number.isFinite(c) && c > 0 ? c : 10;
    }

    function openDev(block: RoadmapBlock): void {
        devBlock = block;
        devTotal = blockCount(block);
        devCorrect = devTotal;
    }

    async function submitDev(): Promise<void> {
        if (!devBlock) {
            return;
        }
        devBusy = true;
        try {
            const total = Math.max(0, Math.round(devTotal));
            const correct = Math.max(0, Math.min(total, Math.round(devCorrect)));
            apply(
                await postJson<RoadmapResponse>("mcatDevCompleteBlock", {
                    block_id: devBlock.id,
                    total,
                    correct,
                }),
            );
            devBlock = null;
            await scrollActive();
        } finally {
            devBusy = false;
        }
    }

    async function resetRoadmap(): Promise<void> {
        apply(await postJson<RoadmapResponse>("mcatDevResetRoadmap"));
        await scrollActive();
    }

    $: devScored = devBlock !== null && devBlock.kind !== "cars";

    onMount(load);
</script>

<div class="mcat-container">
    <header class="head">
        <div>
            <h1 class="mcat-title">Today's Path</h1>
            {#if plan}
                <p class="mcat-subtitle">{doneCount} Of {plan.blocks.length} Done</p>
                {#if plan.phase_label}
                    <span class="phase-badge phase-{plan.phase ?? 'foundation'}">
                        {plan.phase_label}{#if plan.days_until_exam != null}
                            · {plan.days_until_exam} days to exam{/if}
                    </span>
                {/if}
            {/if}
        </div>
        {#if isDev}
            <button class="dev-reset" on:click={resetRoadmap}>Reset roadmap</button>
        {/if}
    </header>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if plan}
        <div class="legend">
            <span>
                <span class="ld" style="background:var(--mcat-cyan)"></span>
                Spaced Review
            </span>
            <span>
                <span class="ld" style="background:var(--mcat-amber)"></span>
                Performance Set
            </span>
            <span>
                <span class="ld" style="background:var(--mcat-blue)"></span>
                Section Practice
            </span>
        </div>

        <div class="unlock" class:on={freePracticeUnlocked}>
            {freePracticeUnlocked
                ? "✓ Extra Practice unlocked"
                : "Finish today's path to unlock Extra Practice"}
        </div>

        <div class="path" bind:this={pathEl} style={`height:${totalH}px`}>
            <svg
                class="track"
                viewBox={`0 0 100 ${totalH}`}
                preserveAspectRatio="none"
                style={`height:${totalH}px`}
            >
                {#each connectors as c (c.key)}
                    <line
                        x1={c.x1}
                        y1={c.y1}
                        x2={c.x2}
                        y2={c.y2}
                        stroke={c.solid ? "var(--mcat-accent)" : "var(--mcat-muted)"}
                        stroke-width="3"
                        stroke-linecap="round"
                        vector-effect="non-scaling-stroke"
                        stroke-dasharray={c.solid ? "none" : "2 8"}
                        style={`--i:${c.key}`}
                    />
                {/each}
            </svg>

            {#if travel}
                <div
                    class="traveler"
                    style={`--sx:${travel.sx}%;--sy:${travel.sy}px;--ex:${travel.ex}%;--ey:${travel.ey}px`}
                ></div>
            {/if}

            {#each plan.blocks as block, i (block.id)}
                {@const m = activityMeta(block)}
                {@const st = statuses[i]}
                <div
                    class="node {st}"
                    style={`left:${posX(i)}%;top:${i * ROW + ROW / 2}px;--c:${m.color};--i:${i}`}
                >
                    {#if st === "active"}<div class="up-next">Up Next</div>{/if}
                    <button
                        class="bubble"
                        on:click={() => start(block, i)}
                        disabled={st === "locked"}
                        aria-label={block.label}
                    >
                        {#if st === "done"}
                            <Icon name="check" size={34} />
                        {:else if st === "locked"}
                            <Icon name="lock" size={24} />
                        {:else}
                            <Icon name={m.icon} size={st === "active" ? 44 : 30} />
                        {/if}
                    </button>
                    <div class="below">
                        <div class="node-label">{block.label}</div>
                        <div class="node-sub">{blockSub(block)}</div>
                        {#if st === "done" && block.score}
                            <div class="node-score" style={`--c:${scoreColor(block)}`}>
                                {block.score.correct}/{block.score.total}{scoreSuffix(
                                    block,
                                )}
                            </div>
                        {:else}
                            <div class="node-time">{block.minutes} Min</div>
                        {/if}
                        {#if isDev && st === "active"}
                            <button class="dev-btn" on:click={() => openDev(block)}>
                                ⚙ Mark done
                            </button>
                        {/if}
                    </div>
                    {#if st === "active" && why}
                        <div class="why-card {posX(i) < 50 ? 'right' : 'left'}">
                            <div class="why-kicker">Why this, now</div>
                            <div class="why-title-row">
                                <span class="why-ic" style={`--c:${m.color}`}>
                                    <Icon name={m.icon} size={14} />
                                </span>
                                <span class="why-title">{why.title}</span>
                            </div>
                            {#if why.current_pct != null}
                                <div class="why-bar">
                                    <div class="why-track">
                                        <div
                                            class="why-fill"
                                            style={`width:${why.current_pct}%;background:${whyTone(
                                                why.current_pct,
                                            )}`}
                                        ></div>
                                        {#if why.target_pct != null}
                                            <div
                                                class="why-tick"
                                                style={`left:${why.target_pct}%`}
                                            ></div>
                                        {/if}
                                    </div>
                                    <div class="why-nums">
                                        <span
                                            style={`color:${whyTone(why.current_pct)}`}
                                        >
                                            {why.current_pct}% now
                                        </span>
                                        {#if why.target_pct != null}
                                            <span class="why-target">
                                                → ~{why.target_pct}%
                                            </span>
                                        {/if}
                                    </div>
                                </div>
                            {:else}
                                <div class="why-nomeasure">
                                    Not measured yet — this set starts your estimate.
                                </div>
                            {/if}
                            {#if why.fact}
                                <div class="why-fact">{why.fact}</div>
                            {/if}
                        </div>
                    {/if}
                </div>
            {/each}

            <div
                class="node finish"
                class:lit={allRequiredDone}
                style={`left:50%;top:${plan.blocks.length * ROW + ROW / 2}px;--i:${plan.blocks.length}`}
            >
                <div class="bubble final">
                    <Icon name={allRequiredDone ? "spark" : "flag"} size={30} />
                </div>
                <div class="below">
                    <div class="node-label">
                        {allRequiredDone
                            ? `${(streak?.count ?? 0) || 1}-day streak!`
                            : "Finish"}
                    </div>
                </div>
            </div>
        </div>
    {/if}

    {#if devBlock}
        <div
            class="dev-backdrop"
            on:click={() => (devBlock = null)}
            on:keydown={(e) => e.key === "Escape" && (devBlock = null)}
            role="button"
            tabindex="-1"
        >
            <div
                class="dev-modal"
                on:click|stopPropagation
                on:keydown|stopPropagation
                role="dialog"
                tabindex="-1"
            >
                <div class="dev-tag">Dev mode</div>
                <h3>{devBlock.label}</h3>
                {#if devScored}
                    <p class="mcat-muted">
                        Enter a score; we'll record it and complete the block.
                    </p>
                    <div class="dev-fields">
                        <label>
                            Correct
                            <input
                                type="number"
                                min="0"
                                max={devTotal}
                                bind:value={devCorrect}
                            />
                        </label>
                        <label>
                            Total
                            <input type="number" min="0" bind:value={devTotal} />
                        </label>
                    </div>
                {:else}
                    <p class="mcat-muted">Mark this block complete.</p>
                {/if}
                <div class="dev-actions">
                    <button class="mcat-btn" on:click={() => (devBlock = null)}>
                        Cancel
                    </button>
                    <button
                        class="mcat-btn mcat-btn-primary"
                        disabled={devBusy}
                        on:click={submitDev}
                    >
                        {devBusy ? "Saving…" : "Mark done"}
                    </button>
                </div>
            </div>
        </div>
    {/if}
</div>

<style lang="scss">
    .head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        margin-bottom: 16px;
    }
    .phase-badge {
        display: inline-block;
        margin-top: 8px;
        font-size: 13px;
        font-weight: 700;
        padding: 5px 12px;
        border-radius: 999px;
        color: var(--mcat-accent);
        background: color-mix(in srgb, var(--mcat-accent) 12%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--mcat-accent) 26%, var(--mcat-border));
    }
    .phase-badge.phase-sharpen {
        color: var(--mcat-amber);
        background: color-mix(in srgb, var(--mcat-amber) 12%, var(--mcat-surface));
        border-color: color-mix(in srgb, var(--mcat-amber) 26%, var(--mcat-border));
    }
    .phase-badge.phase-final {
        color: var(--mcat-red);
        background: color-mix(in srgb, var(--mcat-red) 12%, var(--mcat-surface));
        border-color: color-mix(in srgb, var(--mcat-red) 26%, var(--mcat-border));
    }
    .legend {
        display: flex;
        gap: 18px;
        flex-wrap: wrap;
        font-size: 13px;
        font-weight: 600;
        color: var(--mcat-muted);
        margin-bottom: 14px;
    }
    .legend span {
        display: inline-flex;
        align-items: center;
        gap: 7px;
    }
    .ld {
        width: 10px;
        height: 10px;
        border-radius: 50%;
    }
    .unlock {
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-left: 4px solid var(--mcat-accent);
        border-radius: 10px;
        padding: 10px 14px;
        font-size: 14px;
        font-weight: 600;
        margin-bottom: 20px;
    }
    .unlock.on {
        border-left-color: var(--mcat-green);
        color: var(--mcat-green);
    }
    .path {
        position: relative;
        max-width: 1080px;
        margin: 0 auto;
    }
    .track {
        position: absolute;
        inset: 0;
        width: 100%;
        z-index: 0;
    }
    .node {
        position: absolute;
        transform: translate(-50%, -50%);
        z-index: 1;
        width: 86px;
        height: 86px;
        /* Cascade the nodes in as the path assembles. */
        animation: nodeIn 0.5s cubic-bezier(0.2, 0.85, 0.3, 1.15) backwards;
        animation-delay: calc(var(--i, 0) * 55ms);
    }
    @keyframes nodeIn {
        from {
            opacity: 0;
            transform: translate(-50%, -50%) scale(0.55);
        }
        to {
            opacity: 1;
            transform: translate(-50%, -50%) scale(1);
        }
    }
    /* Connectors fade in (solid lines stay solid; only future ones are dotted). */
    .track line {
        animation: lineIn 0.45s ease backwards;
        animation-delay: calc(var(--i, 0) * 55ms + 150ms);
    }
    @keyframes lineIn {
        from {
            opacity: 0;
        }
        to {
            opacity: 1;
        }
    }
    /* The pulse dot travelling from the last done node into the active one. */
    .traveler {
        position: absolute;
        width: 14px;
        height: 14px;
        border-radius: 50%;
        background: var(--mcat-accent);
        box-shadow: 0 0 0 5px color-mix(in srgb, var(--mcat-accent) 22%, transparent);
        z-index: 2;
        pointer-events: none;
        animation: travel 2.4s ease-in-out infinite;
        animation-delay: 0.6s;
    }
    @keyframes travel {
        0% {
            left: var(--sx);
            top: var(--sy);
            opacity: 0;
            transform: translate(-50%, -50%) scale(0.5);
        }
        18% {
            opacity: 1;
            transform: translate(-50%, -50%) scale(1);
        }
        82% {
            opacity: 1;
            transform: translate(-50%, -50%) scale(1);
        }
        100% {
            left: var(--ex);
            top: var(--ey);
            opacity: 0;
            transform: translate(-50%, -50%) scale(0.5);
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .node,
        .track line {
            animation: none;
        }
        .traveler {
            display: none;
        }
    }
    .bubble {
        appearance: none;
        width: 86px;
        height: 86px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
        background: var(--c);
        box-shadow: 0 8px 20px -6px color-mix(in srgb, var(--c) 60%, transparent);
        transition:
            transform 0.1s ease,
            box-shadow 0.14s ease;
    }
    .bubble:hover:not(:disabled) {
        transform: translateY(-2px);
    }
    .node.done .bubble {
        background: var(--mcat-green);
        box-shadow:
            0 0 0 6px color-mix(in srgb, var(--mcat-green) 18%, transparent),
            0 8px 20px -6px color-mix(in srgb, var(--mcat-green) 55%, transparent);
    }
    .node.active .bubble {
        background: var(--c);
        outline: 3px dashed var(--c);
        outline-offset: 4px;
        box-shadow: 0 0 0 8px color-mix(in srgb, var(--c) 16%, transparent);
        animation: pulse 1.8s ease-in-out infinite;
    }
    /* The current node is the focus of the screen, so it's noticeably bigger.
       translate(-50%,-50%) keeps it centred on the same point as the connectors. */
    .node.active {
        width: 120px;
        height: 120px;
        /* Above neighbouring nodes so the side "Why" card is never clipped. */
        z-index: 5;
    }
    .node.active .bubble {
        width: 120px;
        height: 120px;
    }
    .node.locked .bubble {
        background: var(--mcat-surface-2);
        color: var(--mcat-muted);
        border: 1px solid var(--mcat-border);
        box-shadow: none;
        cursor: not-allowed;
    }
    .node.finish .bubble.final {
        background: var(--mcat-surface-2);
        color: var(--mcat-muted);
        border: 2px dashed var(--mcat-border);
        box-shadow: none;
    }
    .node.finish.lit .bubble.final {
        background: linear-gradient(180deg, #fff7ed, #fed7aa);
        color: #d97706;
        border: 2px solid #f59e0b;
        box-shadow: 0 0 0 7px rgba(245, 158, 11, 0.16);
    }
    @keyframes pulse {
        0%,
        100% {
            box-shadow: 0 0 0 8px color-mix(in srgb, var(--c) 16%, transparent);
        }
        50% {
            box-shadow: 0 0 0 12px color-mix(in srgb, var(--c) 8%, transparent);
        }
    }
    .below {
        position: absolute;
        top: 100%;
        left: 50%;
        transform: translateX(-50%);
        margin-top: 12px;
        width: 180px;
        text-align: center;
    }
    .node-label {
        font-weight: 800;
        font-size: 17px;
        line-height: 1.2;
    }
    .node-sub {
        font-size: 13px;
        color: var(--mcat-muted);
        margin-top: 3px;
    }
    .node-time {
        display: inline-block;
        margin-top: 7px;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-muted);
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
        border-radius: 999px;
        padding: 3px 11px;
    }
    .up-next {
        position: absolute;
        bottom: 100%;
        left: 50%;
        transform: translateX(-50%);
        margin-bottom: 8px;
        font-size: 11px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: #fff;
        background: var(--c);
        border-radius: 999px;
        padding: 3px 10px;
        white-space: nowrap;
    }
    .dev-btn {
        margin-top: 8px;
        border: none;
        background: var(--mcat-accent);
        color: #fff;
        border-radius: 8px;
        padding: 5px 11px;
        font-size: 12.5px;
        font-weight: 700;
        cursor: pointer;
        white-space: nowrap;
    }
    .dev-reset {
        border: none;
        background: var(--mcat-accent);
        color: #fff;
        border-radius: 9px;
        padding: 8px 14px;
        font-size: 14px;
        font-weight: 700;
        cursor: pointer;
    }
    .dev-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(16, 24, 40, 0.45);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 100;
    }
    .dev-modal {
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 16px;
        box-shadow: var(--mcat-shadow);
        padding: 22px;
        width: min(420px, 92vw);
    }
    .dev-tag {
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--mcat-accent);
        margin-bottom: 6px;
    }
    .dev-modal h3 {
        margin: 0 0 6px;
        font-size: 20px;
    }
    .dev-fields {
        display: flex;
        gap: 14px;
        margin-top: 12px;
    }
    .dev-fields label {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-muted);
        flex: 1;
    }
    .dev-fields input {
        border: 1px solid var(--mcat-border);
        border-radius: 10px;
        padding: 10px 12px;
        background: var(--mcat-bg);
        color: var(--mcat-text);
        font: inherit;
        font-size: 16px;
    }
    .dev-actions {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        margin-top: 18px;
    }
    /* Completed-node score tally (green/amber/red by how it went). */
    .node-score {
        display: inline-block;
        margin-top: 6px;
        font-size: 13.5px;
        font-weight: 800;
        color: var(--c);
        white-space: nowrap;
    }
    /* "Why this, now" card beside the current node, explaining the pick. */
    .why-card {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        width: 250px;
        background: var(--mcat-surface);
        border: 1px solid var(--mcat-border);
        border-radius: 16px;
        box-shadow: var(--mcat-shadow);
        padding: 15px 16px;
        text-align: left;
        z-index: 4;
        animation: whyIn 0.4s ease 0.25s backwards;
    }
    .why-card.right {
        left: 100%;
        margin-left: 24px;
    }
    .why-card.left {
        right: 100%;
        margin-right: 24px;
    }
    @keyframes whyIn {
        from {
            opacity: 0;
            transform: translateY(-50%) scale(0.94);
        }
        to {
            opacity: 1;
            transform: translateY(-50%) scale(1);
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .why-card {
            animation: none;
        }
    }
    .why-kicker {
        font-size: 10.5px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--mcat-muted);
        margin-bottom: 9px;
    }
    .why-title-row {
        display: flex;
        align-items: center;
        gap: 9px;
        margin-bottom: 13px;
    }
    .why-ic {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        width: 26px;
        height: 26px;
        border-radius: 8px;
        color: #fff;
        background: var(--c);
    }
    .why-title {
        font-size: 15.5px;
        font-weight: 800;
        line-height: 1.2;
    }
    .why-bar {
        display: flex;
        flex-direction: column;
        gap: 7px;
    }
    .why-track {
        position: relative;
        height: 9px;
        border-radius: 999px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
    }
    .why-fill {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 999px;
        animation: whyGrow 0.7s cubic-bezier(0.2, 0.8, 0.3, 1) 0.35s backwards;
    }
    @keyframes whyGrow {
        from {
            width: 0 !important;
        }
    }
    .why-tick {
        position: absolute;
        top: -3px;
        width: 3px;
        height: 15px;
        border-radius: 2px;
        background: var(--mcat-accent);
        transform: translateX(-50%);
    }
    .why-nums {
        display: flex;
        justify-content: space-between;
        font-size: 12.5px;
        font-weight: 700;
    }
    .why-target {
        color: var(--mcat-accent);
    }
    .why-nomeasure {
        font-size: 12.5px;
        font-weight: 600;
        color: var(--mcat-muted);
        line-height: 1.4;
    }
    .why-fact {
        margin-top: 13px;
        padding-top: 11px;
        border-top: 1px solid var(--mcat-border);
        font-size: 12.5px;
        font-weight: 600;
        color: var(--mcat-muted);
        line-height: 1.4;
    }
    /* On a narrow webview the side card would overflow — drop it below instead. */
    @media (max-width: 720px) {
        .why-card,
        .why-card.left,
        .why-card.right {
            position: static;
            transform: none;
            width: 100%;
            max-width: 260px;
            margin: 14px auto 0;
        }
    }
</style>
