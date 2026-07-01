<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Account: view your profile, adjust daily study time (rebuilds the roadmap),
and see your streak plus the three scores.
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "../lib/api";
    import EvidenceCard from "../lib/EvidenceCard.svelte";
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
        await postJson<{ profile: Profile }>("mcatSaveProfile", {
            ai_enabled: next,
        });
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

    function hours(mins: number): string {
        if (mins % 60 === 0) {
            return `${mins / 60} hr`;
        }
        return `${(mins / 60).toFixed(1)} hr`;
    }

    async function logout(): Promise<void> {
        await postJson("mcatSaveProfile", { logged_in: false });
        await goto("/mcat");
    }

    onMount(load);
</script>

<div class="mcat-container">
    <header class="mcat-header">
        <div>
            <h1 class="mcat-title">Account</h1>
            <p class="mcat-subtitle">
                Your profile, daily commitment, streak and scores.
            </p>
        </div>
        <button class="mcat-btn logout" on:click={logout}>Log out</button>
    </header>

    {#if loading}
        <div class="mcat-card">Loading…</div>
    {:else if data}
        <section class="top">
            <div class="mcat-card identity">
                <div class="avatar">
                    {(data.profile.name ?? "?").slice(0, 1).toUpperCase()}
                </div>
                <div>
                    <div class="name">{data.profile.name ?? "Your account"}</div>
                    {#if data.profile.email}<div class="mcat-muted email">
                            {data.profile.email}
                        </div>{/if}
                </div>
            </div>
            <div class="mcat-card streak-card">
                <div class="streak-num">🔥 {data.streak.count}</div>
                <div class="mcat-muted">day streak</div>
            </div>
        </section>

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
                            <option value={opt}>
                                {hours(opt)}{opt === RECOMMENDED
                                    ? " (recommended)"
                                    : ""}
                            </option>
                        {/each}
                    </select>
                </label>
            </div>
            <p class="mcat-muted note">2 hrs/day recommended — blocks resize to fit.</p>
            <div class="save-row">
                <button
                    class="mcat-btn mcat-btn-primary"
                    disabled={saving}
                    on:click={save}
                >
                    {saving ? "Saving…" : "Save changes"}
                </button>
                {#if saved}<span class="mcat-good saved">
                        ✓ Saved & roadmap updated
                    </span>{/if}
            </div>
        </div>

        <div class="mcat-card ai-card">
            <div class="ai-row">
                <div>
                    <h2>AI features</h2>
                    <p class="mcat-muted note">
                        Personalized reasoning feedback, CARS debate, and a study coach.
                        Turn off for classic mode — everything still works and still
                        scores, with no AI calls.
                    </p>
                </div>
                <Switch
                    checked={aiEnabled}
                    label="AI features"
                    on:toggle={(e) => toggleAi(e.detail)}
                />
            </div>
        </div>

        <h2 class="scores-heading">Your scores</h2>
        {#if data.scores}
            <section class="scores">
                <EvidenceCard
                    id="memory"
                    title="Memory Recall"
                    icon="brain"
                    block={data.scores.memory}
                />
                <EvidenceCard
                    id="performance"
                    title="Applied Under Exam Conditions"
                    icon="target"
                    block={data.scores.performance}
                />
                <EvidenceCard
                    id="readiness"
                    title="Overall Readiness"
                    icon="gauge"
                    block={data.scores.readiness}
                    scaleMin={472}
                    scaleMax={528}
                />
            </section>
        {:else}
            <div class="mcat-card mcat-muted">
                Scores will appear once you've installed content and done some practice.
            </div>
        {/if}
    {/if}
</div>

<style lang="scss">
    .top {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 16px;
        margin-bottom: 12px;
    }
    .identity {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 14px;
    }
    .avatar {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        font-size: 20px;
        color: #fff;
        background: linear-gradient(135deg, var(--mcat-accent), var(--mcat-accent-2));
    }
    .name {
        font-weight: 700;
        font-size: 20px;
    }
    .email {
        font-size: 15px;
    }
    .streak-card {
        text-align: center;
        min-width: 120px;
        display: flex;
        flex-direction: column;
        justify-content: center;
    }
    .streak-num {
        font-size: 36px;
        font-weight: 800;
    }
    .settings {
        margin-bottom: 16px;
    }
    .settings h2 {
        margin: 0 0 12px;
        font-size: 19px;
    }
    .ai-card {
        margin-bottom: 16px;
    }
    .ai-card h2 {
        margin: 0 0 6px;
        font-size: 19px;
    }
    .ai-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 20px;
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
        font-size: 15px;
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
    .note {
        font-size: 15px;
        margin: 10px 0 0;
    }
    .save-row {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-top: 12px;
    }
    .saved {
        font-size: 13px;
        font-weight: 600;
    }
    .scores-heading {
        font-size: 19px;
        margin: 4px 0 10px;
    }
    .scores {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 14px;
    }
    @media (max-width: 820px) {
        .scores {
            grid-template-columns: 1fr;
        }
    }

    /* Cards slide in from the side, staggered, on load. */
    .top,
    .settings,
    .ai-card,
    .scores-heading,
    .scores {
        animation: acct-slide 0.5s cubic-bezier(0.2, 0.8, 0.3, 1) both;
    }
    .top {
        animation-delay: 0.05s;
    }
    .settings {
        animation-delay: 0.12s;
    }
    .ai-card {
        animation-delay: 0.19s;
    }
    .scores-heading {
        animation-delay: 0.26s;
    }
    .scores {
        animation-delay: 0.33s;
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
        .top,
        .settings,
        .ai-card,
        .scores-heading,
        .scores {
            animation: none;
        }
    }
</style>
