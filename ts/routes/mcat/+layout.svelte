<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
-->
<script lang="ts">
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { onMount } from "svelte";

    import "@fontsource-variable/nunito";
    import "./mcat-base.scss";
    import { playClick, unlockSound } from "./lib/sound";
    import { darkMode } from "./lib/theme";

    onMount(() => {
        function onPointer(e: PointerEvent): void {
            unlockSound();
            const t = e.target as HTMLElement | null;
            if (t?.closest("button, a, [role='button']")) {
                playClick();
            }
        }
        document.addEventListener("pointerdown", onPointer, true);
        return () => document.removeEventListener("pointerdown", onPointer, true);
    });

    // Dashboard is home; it carries a big adaptive "what to do next" CTA that
    // points to Today's Path (or Extra Practice once the path is done).
    const items = [
        { id: "dashboard", label: "Dashboard" },
        { id: "roadmap", label: "Today's Path" },
        { id: "extra", label: "Extra Practice" },
        { id: "account", label: "Account" },
    ];

    // Sub-pages reached from a tab still light that tab up.
    const EXTRA_SUBPAGES = ["mini", "flashcards", "cars"];

    $: path = $page.url.pathname;
    // Tasks launched from the roadmap carry from=roadmap so the nav stays on
    // "Roadmap" instead of lighting up "Extra Practice".
    $: fromRoadmap = $page.url.searchParams.get("from") === "roadmap";
    // Hide the bar on the splash router and onboarding (pre-login).
    $: showNav = !(
        path === "/mcat" ||
        path === "/mcat/" ||
        path.startsWith("/mcat/onboarding")
    );
    function computeActive(p: string, fromRm: boolean): string {
        const direct = items.find((it) => p.startsWith(`/mcat/${it.id}`))?.id;
        if (direct) {
            return direct;
        }
        if (EXTRA_SUBPAGES.some((s) => p.startsWith(`/mcat/${s}`))) {
            return fromRm ? "roadmap" : "extra";
        }
        return "";
    }
    $: active = computeActive(path, fromRoadmap);

    function nav(id: string): void {
        goto(`/mcat/${id}`);
    }
</script>

<div class="mcat-app" class:dark={$darkMode}>
    {#if showNav}
        <header class="mcat-topbar">
            <nav class="topnav">
                {#each items as item (item.id)}
                    <button
                        class="topnav-item"
                        class:active={item.id === active}
                        on:click={() => nav(item.id)}
                    >
                        {item.label}
                    </button>
                {/each}
            </nav>
        </header>
    {/if}
    <div class="mcat-scroll">
        <slot />
    </div>
</div>

<style lang="scss">
    .mcat-topbar {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 6px 18px;
        min-height: 46px;
        background: color-mix(in srgb, var(--mcat-surface) 90%, transparent);
        border-bottom: 1px solid var(--mcat-border);
        backdrop-filter: saturate(1.3) blur(8px);
    }
    /* Tabs are centered in the bar. */
    .topnav {
        position: absolute;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 4px;
    }
    .topnav-item {
        border: 1px solid transparent;
        background: transparent;
        color: var(--mcat-muted);
        border-radius: 9px;
        padding: 7px 16px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        white-space: nowrap;
        transition:
            background 0.12s ease,
            color 0.12s ease;
    }
    .topnav-item:hover {
        background: var(--mcat-bg);
        color: var(--mcat-text);
    }
    .topnav-item.active {
        background: var(--mcat-bg);
        color: var(--mcat-accent);
        border-color: var(--mcat-border);
    }
</style>
