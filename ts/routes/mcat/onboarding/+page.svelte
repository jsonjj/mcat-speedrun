<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Consumer onboarding: sign up or log in, set your exam date, then head into the
placement test. The plan defaults to 2 hours/day (adjustable later in Account).
No AI and no remote server yet - this sets up your local profile.
-->
<script lang="ts">
    import { goto } from "$app/navigation";

    import { postJson } from "../lib/api";
    import type { Profile } from "../lib/types";

    const RECOMMENDED_MINUTES = 120;

    let step: "welcome" | "signup" | "login" | "placement" = "welcome";
    let authProvider: "password" | "google" = "password";
    let name = "";
    let email = "";
    let password = "";
    let examDate = "";
    let loginEmail = "";
    let loginPassword = "";
    let busy = false;
    let error = "";

    function startSignup(provider: "password" | "google"): void {
        authProvider = provider;
        error = "";
        step = "signup";
    }

    $: daysUntil = examDate ? daysBetween(examDate) : null;

    function daysBetween(iso: string): number | null {
        const exam = new Date(iso + "T00:00:00");
        if (isNaN(exam.getTime())) {
            return null;
        }
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return Math.round((exam.getTime() - today.getTime()) / 86400000);
    }

    async function createAccount(): Promise<void> {
        if (!name.trim() || !examDate) {
            error = "Please enter your name and exam date.";
            return;
        }
        if (authProvider === "password" && password.length < 6) {
            error = "Password must be at least 6 characters.";
            return;
        }
        if (daysUntil !== null && daysUntil < 0) {
            error = "Your exam date is in the past — pick an upcoming date.";
            return;
        }
        if (authProvider === "password" && !email.trim()) {
            error = "Enter your email so your account syncs across devices.";
            return;
        }
        error = "";
        busy = true;
        try {
            if (authProvider === "password") {
                // Creates a real Firebase account so progress syncs to the phone.
                const res = await postJson<{ ok: boolean; error?: string }>(
                    "mcatSignup",
                    {
                        name: name.trim(),
                        email: email.trim(),
                        password,
                        exam_date: examDate,
                        daily_minutes: RECOMMENDED_MINUTES,
                    },
                );
                if (!res.ok) {
                    error = res.error ?? "Sign-up failed.";
                    return;
                }
            } else {
                await postJson<{ profile: Profile }>("mcatSaveProfile", {
                    name: name.trim(),
                    email: email.trim() || null,
                    password: null,
                    auth_provider: "google",
                    exam_date: examDate,
                    daily_minutes: RECOMMENDED_MINUTES,
                    onboarding_done: true,
                    logged_in: true,
                });
            }
            await postJson("mcatBootstrap");
            step = "placement";
        } catch (e) {
            error = `Something went wrong: ${e instanceof Error ? e.message : e}`;
        } finally {
            busy = false;
        }
    }

    async function logInWithGoogle(): Promise<void> {
        error = "";
        busy = true;
        try {
            const res = await postJson<{ ok: boolean; error?: string }>("mcatLogin", {
                provider: "google",
            });
            if (!res.ok) {
                error = res.error ?? "Login failed.";
                return;
            }
            await goto("/mcat/dashboard");
        } catch (e) {
            error = `Something went wrong: ${e instanceof Error ? e.message : e}`;
        } finally {
            busy = false;
        }
    }

    async function logIn(): Promise<void> {
        if (!loginEmail.trim() || !loginPassword) {
            error = "Enter your email and password.";
            return;
        }
        error = "";
        busy = true;
        try {
            const res = await postJson<{ ok: boolean; error?: string }>("mcatLogin", {
                email: loginEmail.trim(),
                password: loginPassword,
            });
            if (!res.ok) {
                error = res.error ?? "Login failed.";
                return;
            }
            await goto("/mcat/dashboard");
        } catch (e) {
            error = `Something went wrong: ${e instanceof Error ? e.message : e}`;
        } finally {
            busy = false;
        }
    }
</script>

<div class="mcat-container onboarding">
    {#if step === "welcome"}
        <div class="hero">
            <div class="logo">MCAT Speedrun</div>
            <h1>Memory. Performance. Readiness.</h1>
            <p class="mcat-muted lead">
                What you know, what you can apply, your range today.
            </p>
        </div>
        <div class="mcat-card welcome-card">
            <button
                class="mcat-btn mcat-btn-primary big"
                on:click={() => startSignup("password")}
            >
                Create an account
            </button>
            <button class="google-btn big" on:click={() => startSignup("google")}>
                <svg class="g-icon" viewBox="0 0 18 18" aria-hidden="true">
                    <path
                        fill="#4285F4"
                        d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"
                    />
                    <path
                        fill="#34A853"
                        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.02-3.7H.96v2.34A9 9 0 0 0 9 18z"
                    />
                    <path
                        fill="#FBBC05"
                        d="M3.98 10.72a5.4 5.4 0 0 1 0-3.44V4.94H.96a9 9 0 0 0 0 8.12l3.02-2.34z"
                    />
                    <path
                        fill="#EA4335"
                        d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.94l3.02 2.34C4.68 5.16 6.66 3.58 9 3.58z"
                    />
                </svg>
                Continue with Google
            </button>
            <button class="mcat-btn big" on:click={() => (step = "login")}>
                I already have an account
            </button>
        </div>
    {:else if step === "signup"}
        <div class="hero">
            <div class="logo">
                {authProvider === "google" ? "Sign up with Google" : "Create account"}
            </div>
            <h1>Let's build your plan.</h1>
            <p class="mcat-muted lead">
                Starts at <strong>2 hrs/day</strong>
                — adjust anytime in Account.
            </p>
        </div>
        <div class="mcat-card form">
            {#if authProvider === "google"}
                <div class="google-note">
                    Continuing with Google — no password needed.
                </div>
            {/if}
            <label>
                Your name
                <input type="text" bind:value={name} placeholder="e.g. Jordan" />
            </label>
            <label>
                Email {#if authProvider === "password"}<span
                        class="mcat-muted optional"
                    >
                        (optional)
                    </span>{/if}
                <input type="email" bind:value={email} placeholder="you@example.com" />
            </label>
            {#if authProvider === "password"}
                <label>
                    Password
                    <input
                        type="password"
                        bind:value={password}
                        placeholder="At least 6 characters"
                    />
                </label>
            {/if}
            <label>
                MCAT exam date
                <input type="date" bind:value={examDate} />
            </label>
            {#if daysUntil !== null && daysUntil >= 0}
                <div class="countdown mcat-pill">{daysUntil} days until your exam</div>
            {/if}
            {#if error}<p class="mcat-bad err">{error}</p>{/if}
            <button
                class="mcat-btn mcat-btn-primary big"
                disabled={busy}
                on:click={createAccount}
            >
                {busy ? "Setting up your question bank…" : "Create my account"}
            </button>
            <button class="mcat-btn ghost" on:click={() => (step = "welcome")}>
                Back
            </button>
        </div>
    {:else if step === "login"}
        <div class="hero">
            <div class="logo">Log in</div>
            <h1>Welcome back.</h1>
            <p class="mcat-muted lead">
                Log in to pick up your plan where you left off.
            </p>
        </div>
        <div class="mcat-card form">
            <label>
                Email
                <input
                    type="email"
                    bind:value={loginEmail}
                    placeholder="you@example.com"
                />
            </label>
            <label>
                Password
                <input
                    type="password"
                    bind:value={loginPassword}
                    placeholder="Your password"
                />
            </label>
            {#if error}<p class="mcat-bad err">{error}</p>{/if}
            <button
                class="mcat-btn mcat-btn-primary big"
                disabled={busy}
                on:click={logIn}
            >
                {busy ? "Logging in…" : "Log in"}
            </button>
            <div class="or"><span>or</span></div>
            <button class="google-btn big" disabled={busy} on:click={logInWithGoogle}>
                <svg class="g-icon" viewBox="0 0 18 18" aria-hidden="true">
                    <path
                        fill="#4285F4"
                        d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z"
                    />
                    <path
                        fill="#34A853"
                        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.02-3.7H.96v2.34A9 9 0 0 0 9 18z"
                    />
                    <path
                        fill="#FBBC05"
                        d="M3.98 10.72a5.4 5.4 0 0 1 0-3.44V4.94H.96a9 9 0 0 0 0 8.12l3.02-2.34z"
                    />
                    <path
                        fill="#EA4335"
                        d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.94l3.02 2.34C4.68 5.16 6.66 3.58 9 3.58z"
                    />
                </svg>
                Continue with Google
            </button>
            <button class="mcat-btn ghost" on:click={() => (step = "welcome")}>
                Back
            </button>
        </div>
    {:else}
        <div class="hero">
            <div class="logo">Placement test</div>
            <h1>Find your starting line.</h1>
            <p class="mcat-muted lead">
                A quick test across all four sections builds your first plan.
            </p>
        </div>
        <div class="mcat-card next-card">
            <p>
                You're all set, <strong>{name || "future doctor"}</strong>
                . Ready to calibrate?
            </p>
            <div class="row">
                <button
                    class="mcat-btn mcat-btn-primary big"
                    on:click={() => goto("/mcat/diagnostic")}
                >
                    Start placement test
                </button>
                <button class="mcat-btn" on:click={() => goto("/mcat/dashboard")}>
                    Skip for now
                </button>
            </div>
        </div>
    {/if}
</div>

<style lang="scss">
    .onboarding {
        max-width: 640px;
    }
    .hero {
        text-align: center;
        margin: 28px 0 20px;
    }
    .logo {
        font-weight: 800;
        font-size: 15px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--mcat-accent);
    }
    .hero h1 {
        font-size: 36px;
        font-weight: 800;
        letter-spacing: -0.02em;
        margin: 8px 0 10px;
    }
    .lead {
        font-size: 17px;
        line-height: 1.6;
        margin: 0 auto;
        max-width: 540px;
    }
    .welcome-card {
        display: flex;
        flex-direction: column;
        gap: 12px;
    }
    .google-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
        width: 100%;
        border: 1px solid var(--mcat-border);
        background: var(--mcat-surface);
        color: var(--mcat-text);
        border-radius: 10px;
        font-weight: 600;
        cursor: pointer;
        transition: background 0.12s ease;
    }
    .google-btn:hover {
        background: var(--mcat-bg);
    }
    .g-icon {
        width: 18px;
        height: 18px;
        flex: 0 0 auto;
    }
    .google-note {
        font-size: 14px;
        color: var(--mcat-muted);
        background: var(--mcat-bg);
        border: 1px solid var(--mcat-border);
        border-radius: 10px;
        padding: 10px 12px;
    }
    .or {
        display: flex;
        align-items: center;
        text-align: center;
        gap: 10px;
        color: var(--mcat-muted);
        font-size: 13px;
    }
    .or::before,
    .or::after {
        content: "";
        flex: 1;
        height: 1px;
        background: var(--mcat-border);
    }
    .form {
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    label {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 15px;
        font-weight: 600;
        color: var(--mcat-muted);
    }
    .optional {
        font-weight: 400;
    }
    input {
        border: 1px solid var(--mcat-border);
        border-radius: 10px;
        padding: 12px 13px;
        background: var(--mcat-bg);
        color: var(--mcat-text);
        font: inherit;
        font-size: 15px;
    }
    .countdown {
        align-self: flex-start;
        color: var(--mcat-accent);
        border-color: rgba(79, 70, 229, 0.3);
    }
    .big {
        padding: 14px 20px;
        font-size: 16px;
    }
    .ghost {
        border: none;
        background: transparent;
        color: var(--mcat-muted);
        align-self: center;
    }
    .err {
        margin: 0;
        font-size: 13px;
    }
    .next-card {
        text-align: center;
        display: flex;
        flex-direction: column;
        gap: 14px;
    }
    .row {
        display: flex;
        gap: 10px;
        justify-content: center;
        flex-wrap: wrap;
    }
</style>
