<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Entry router: decides where a returning user lands based on their progress
(onboarding -> placement diagnostic -> dashboard).
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { onMount } from "svelte";

    import { postJson } from "./lib/api";
    import type { Profile } from "./lib/types";

    onMount(async () => {
        try {
            const { profile } = await postJson<{ profile: Profile }>("mcatGetProfile");
            if (!profile.onboarding_done || !profile.logged_in) {
                await goto("/mcat/onboarding");
            } else if (!profile.diagnostic_done) {
                await goto("/mcat/diagnostic");
            } else {
                // Home is the dashboard; it carries a big "what to do next" CTA.
                await goto("/mcat/dashboard");
            }
        } catch (_e) {
            await goto("/mcat/onboarding");
        }
    });
</script>

<div class="splash">
    <div class="logo">MCAT Speedrun</div>
    <div class="tagline">Memory. Performance. Readiness.</div>
    <div class="dots">
        <span></span>
        <span></span>
        <span></span>
    </div>
</div>

<style lang="scss">
    .splash {
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
    }
    .logo {
        font-size: 34px;
        font-weight: 800;
        letter-spacing: -0.02em;
        background: linear-gradient(135deg, var(--mcat-accent), var(--mcat-accent-2));
        -webkit-background-clip: text;
        background-clip: text;
        -webkit-text-fill-color: transparent;
    }
    .tagline {
        color: var(--mcat-muted);
        font-size: 14px;
    }
    .dots {
        display: flex;
        gap: 6px;
        margin-top: 16px;
    }
    .dots span {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: var(--mcat-accent);
        opacity: 0.3;
        animation: pulse 1.2s infinite ease-in-out;
    }
    .dots span:nth-child(2) {
        animation-delay: 0.2s;
    }
    .dots span:nth-child(3) {
        animation-delay: 0.4s;
    }
    @keyframes pulse {
        0%,
        100% {
            opacity: 0.3;
        }
        50% {
            opacity: 1;
        }
    }
</style>
