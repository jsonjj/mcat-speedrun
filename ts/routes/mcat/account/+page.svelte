<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Account: profile + streak and settings only. Scores/progress live on the Scores
tab and its detail pages, so this page stays focused on identity + commitment.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import DaysRing from "../lib/DaysRing.svelte";
    import Switch from "../lib/Switch.svelte";
    import type { AccountData, Profile } from "../lib/types";

    const RECOMMENDED = 120;
    const TIME_OPTIONS = [30, 45, 60, 90, 120, 150, 180];

    let data: AccountData | null = null;
    let loading = true;
    let saving = false;
    let saved = false;
    let examDate = "";
    let dailyMinutes = RECOMMENDED;
    let aiEnabled = true;

    async function load(): Promise<void> {
        loading = true;
        data = await postJson<AccountData>("mcatAccount");
        examDate = data.profile.exam_date ?? "";
        dailyMinutes = data.profile.daily_minutes ?? RECOMMENDED;
        aiEnabled = data.profile.ai_enabled ?? true;
        loading = false;
    }

    async function toggleAi(next: boolean): Promise<void> {
        aiEnabled = next;
        await postJson<{ profile: Profile }>("mcatSaveProfile", { ai_enabled: next });
    }

    async function save(): Promise<void> {
        saving = true;
        saved = false;
        try {
            await postJson<{ profile: Profile }>("mcatSaveProfile", {
                exam_date: examDate || null,
                daily_minutes: Number(dailyMinutes),
            });
            // Rebuild the roadmap so block sizes/counts reflect the new time.
            await postJson("mcatRebuildRoadmap");
            await load();
            saved = true;
        } finally {
            saving = false;
        }
    }

    async function logout(): Promise<void> {
        await postJson("mcatSaveProfile", { logged_in: false });
        await goto("/mcat");
    }

    function hours(mins: number): string {
        return mins % 60 === 0 ? `${mins / 60} hr` : `${(mins / 60).toFixed(1)} hr`;
    }

    function daysUntil(iso: string | null): number | null {
        if (!iso) {
            return null;
        }
        const exam = new Date(iso + "T00:00:00");
        if (isNaN(exam.getTime())) {
            return null;
        }
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return Math.max(0, Math.round((exam.getTime() - today.getTime()) / 86400000));
    }

    // Seven dots (Mon→Sun); fill the current streak's days within this week.
    function weekDots(count: number, last: string | null): boolean[] {
        const dots = Array(7).fill(false);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayIso = today.toISOString().slice(0, 10);
        const todayIdx = (today.getDay() + 6) % 7; // Mon=0 … Sun=6
        const span = last === todayIso ? Math.min(count, todayIdx + 1) : 0;
        for (let k = 0; k < span; k++) {
            dots[todayIdx - k] = true;
        }
        return dots;
    }

    $: days = data ? daysUntil(data.profile.exam_date ?? null) : null;
    $: dots = data ? weekDots(data.streak.count, data.streak.last_completed_date) : [];
    $: remainingHr = Math.max(0, (RECOMMENDED - dailyMinutes) / 60);
    $: paceFill = Math.min(100, (dailyMinutes / RECOMMENDED) * 100);
    $: initial = (data?.profile.name ?? "?").slice(0, 1).toUpperCase();

    const AI_FEATURES = [
        { label: "Reasoning feedback", color: "var(--mcat-blue)" },
        { label: "CARS debate", color: "var(--mcat-red)" },
        { label: "Study coach", color: "var(--mcat-green)" },
    ];

    onMount(load);
</script>

<div class="mcat-container">
    <header class="head">
        <div>
            <h1 class="mcat-title">Account</h1>
            <p class="mcat-subtitle">Your profile and study commitment.</p>
        </div>
        <button class="mcat-btn logout" on:click={logout}>Log out</button>
    </header>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if data}
        <!-- Profile -->
        <div class="mcat-card profile">
            <div class="ring-slot"><DaysRing {days} /></div>
            <div class="identity">
                <div class="avatar">{initial}</div>
                <div>
                    <div class="name">{data.profile.name ?? "Your account"}</div>
                    {#if data.profile.email}
                        <div class="mcat-muted email">{data.profile.email}</div>
                    {/if}
                </div>
            </div>
            <div class="streak">
                <div class="streak-top">
                    <span class="flame">🔥</span>
                    <span class="streak-num">{data.streak.count}</span>
                </div>
                <div class="dots">
                    {#each dots as on, di (di)}
                        <span class="wd" class:on></span>
                    {/each}
                </div>
                <div class="mcat-muted streak-lab">this week</div>
            </div>
        </div>

        <!-- Study settings -->
        <div class="mcat-card settings">
            <h2>Study settings</h2>
            <div class="settings-grid">
                <label>
                    MCAT exam date
                    <input type="date" bind:value={examDate} />
                </label>
                <label>
                    Daily study time
                    <select bind:value={dailyMinutes}>
                        {#each TIME_OPTIONS as opt (opt)}
                            <option value={opt}>{hours(opt)}</option>
                        {/each}
                    </select>
                </label>
            </div>

            <div class="pace">
                <div class="pace-top">
                    <span class="pace-lab">Your pace</span>
                    <span class="mcat-muted">
                        {hours(dailyMinutes)} of {hours(RECOMMENDED)} recommended
                    </span>
                </div>
                <div class="pace-track">
                    <div class="pace-fill" style={`width:${paceFill}%`}></div>
                    <div class="pace-goal"><span>goal</span></div>
                </div>
                {#if remainingHr > 0}
                    <div class="pace-note">
                        {remainingHr.toFixed(1)} hr more to hit the recommended pace
                    </div>
                {:else}
                    <div class="pace-note good">✓ You're at the recommended pace</div>
                {/if}
            </div>

            <div class="save-row">
                <button
                    class="mcat-btn mcat-btn-primary"
                    disabled={saving}
                    on:click={save}
                >
                    {saving ? "Saving…" : "Save changes"}
                </button>
                {#if saved}
                    <span class="mcat-good saved">✓ Saved & roadmap updated</span>
                {/if}
            </div>
        </div>

        <!-- AI features -->
        <div class="mcat-card ai-card">
            <div class="ai-row">
                <h2>AI features</h2>
                <Switch
                    checked={aiEnabled}
                    label="AI features"
                    on:toggle={(e) => toggleAi(e.detail)}
                />
            </div>
            <p class="mcat-muted note">
                Off = classic mode. Everything still works and still scores.
            </p>
            <div class="ai-chips" class:off={!aiEnabled}>
                {#each AI_FEATURES as f (f.label)}
                    <span class="chip">
                        <span class="chip-dot" style={`background:${f.color}`}></span>
                        {f.label}
                    </span>
                {/each}
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
        margin-bottom: 18px;
    }
    /* Profile row: ring · identity · streak */
    .profile {
        display: flex;
        align-items: center;
        gap: 24px;
        margin-bottom: 16px;
    }
    .ring-slot {
        flex-shrink: 0;
    }
    .identity {
        display: flex;
        align-items: center;
        gap: 16px;
        flex: 1;
        min-width: 0;
    }
    .avatar {
        width: 56px;
        height: 56px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        font-size: 24px;
        color: #fff;
        flex-shrink: 0;
        background: linear-gradient(135deg, var(--mcat-accent), var(--mcat-accent-2));
    }
    .name {
        font-weight: 800;
        font-size: 24px;
        line-height: 1.15;
    }
    .email {
        font-size: 15px;
        margin-top: 2px;
    }
    .streak {
        text-align: center;
        padding-left: 24px;
        border-left: 1px solid var(--mcat-border);
        align-self: stretch;
        display: flex;
        flex-direction: column;
        justify-content: center;
    }
    .streak-top {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
    }
    .streak-num {
        font-size: 30px;
        font-weight: 800;
        color: var(--mcat-amber);
    }
    .dots {
        display: flex;
        gap: 5px;
        margin: 8px 0 5px;
    }
    .wd {
        width: 14px;
        height: 14px;
        border-radius: 5px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
    }
    .wd.on {
        background: var(--mcat-green);
        border-color: var(--mcat-green);
    }
    .streak-lab {
        font-size: 12px;
    }

    /* Settings */
    .settings {
        margin-bottom: 16px;
    }
    .settings h2,
    .ai-card h2 {
        margin: 0 0 12px;
        font-size: 19px;
    }
    .settings-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 16px;
    }
    label {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 14px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    input,
    select {
        border: 1px solid var(--mcat-border);
        border-radius: 10px;
        padding: 11px 13px;
        background: var(--mcat-bg);
        color: var(--mcat-text);
        font: inherit;
        font-size: 15px;
    }
    /* Pace-to-goal bar */
    .pace {
        margin-top: 18px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
        border-radius: 12px;
        padding: 14px 16px;
    }
    .pace-top {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        font-size: 14px;
        margin-bottom: 10px;
    }
    .pace-lab {
        font-weight: 700;
    }
    .pace-track {
        position: relative;
        height: 10px;
        border-radius: 999px;
        background: var(--mcat-track);
    }
    .pace-fill {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 999px;
        background: var(--mcat-amber);
        animation: paceGrow 0.7s cubic-bezier(0.2, 0.8, 0.3, 1);
    }
    @keyframes paceGrow {
        from {
            width: 0 !important;
        }
    }
    .pace-goal {
        position: absolute;
        right: 0;
        top: -4px;
        bottom: -4px;
        width: 3px;
        border-radius: 2px;
        background: var(--mcat-green);
    }
    .pace-goal span {
        position: absolute;
        top: -16px;
        right: -6px;
        font-size: 10px;
        font-weight: 800;
        color: var(--mcat-green);
    }
    .pace-note {
        margin-top: 12px;
        font-size: 13px;
        font-weight: 700;
        color: var(--mcat-amber);
    }
    .pace-note.good {
        color: var(--mcat-green);
    }
    .save-row {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-top: 16px;
    }
    .saved {
        font-size: 13px;
        font-weight: 600;
    }

    /* AI features */
    .ai-card {
        margin-bottom: 8px;
    }
    .ai-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 20px;
        margin-bottom: 4px;
    }
    .ai-row h2 {
        margin: 0;
    }
    .note {
        font-size: 14px;
        margin: 0 0 14px;
    }
    .ai-chips {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        transition: opacity 0.2s ease;
    }
    .ai-chips.off {
        opacity: 0.45;
    }
    .chip {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        background: var(--mcat-surface-2);
        border: 1px solid var(--mcat-border);
        border-radius: 10px;
        padding: 9px 14px;
        font-size: 14px;
        font-weight: 700;
    }
    .chip-dot {
        width: 10px;
        height: 10px;
        border-radius: 3px;
    }

    @media (max-width: 820px) {
        .profile {
            flex-wrap: wrap;
            justify-content: center;
            text-align: center;
        }
        .streak {
            border-left: none;
            padding-left: 0;
        }
    }

    /* Staggered slide-in on load. */
    .profile,
    .settings,
    .ai-card {
        animation: acct-slide 0.5s cubic-bezier(0.2, 0.8, 0.3, 1) both;
    }
    .profile {
        animation-delay: 0.04s;
    }
    .settings {
        animation-delay: 0.1s;
    }
    .ai-card {
        animation-delay: 0.16s;
    }
    @keyframes acct-slide {
        from {
            opacity: 0;
            transform: translateX(-22px);
        }
        to {
            opacity: 1;
            transform: none;
        }
    }
    @media (prefers-reduced-motion: reduce) {
        .profile,
        .settings,
        .ai-card,
        .pace-fill {
            animation: none;
        }
    }
</style>
