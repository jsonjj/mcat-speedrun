<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

A once-per-day diagnostic launcher for the Extra Practice page. It's the same
placement test as onboarding, but the results are folded into the existing
scores (never a reset), so each run refines the estimate. Availability is synced
across devices, so one diagnostic per day counts for both apps.
-->
<script lang="ts">
    import { goto } from "$app/navigation";

    export let available: boolean;

    const lengths = [
        { kind: "quick", label: "Quick", detail: "~12 Q" },
        { kind: "standard", label: "Standard", detail: "~20 Q" },
        { kind: "best_estimate", label: "Best Estimate", detail: "~40 Q" },
    ];

    function start(kind: string): void {
        goto(`/mcat/diagnostic?kind=${kind}&from=extra`);
    }
</script>

<div class="daily">
    {#if available}
        <div class="d-title">Take a daily diagnostic</div>
        <div class="d-sub">
            One per day — it adds to your scores to sharpen the estimate. Pick a length:
        </div>
        <div class="d-opts">
            {#each lengths as l (l.kind)}
                <button class="d-opt" on:click={() => start(l.kind)}>
                    <span class="d-opt-label">{l.label}</span>
                    <span class="d-opt-detail">{l.detail}</span>
                </button>
            {/each}
        </div>
    {:else}
        <div class="d-done">
            <span class="d-check">✓</span>
            <div>
                <div class="d-title">Daily diagnostic done</div>
                <div class="d-sub">
                    Come back tomorrow — your scores keep refining as you practice.
                </div>
            </div>
        </div>
    {/if}
</div>

<style lang="scss">
    .daily {
        width: 100%;
        max-width: 640px;
        margin: 10px auto 0;
        background: color-mix(in srgb, var(--mcat-blue) 8%, var(--mcat-surface));
        border: 1px solid color-mix(in srgb, var(--mcat-blue) 24%, var(--mcat-border));
        border-radius: 16px;
        padding: 18px 20px;
        text-align: center;
    }
    .d-title {
        font-weight: 800;
        font-size: 17px;
    }
    .d-sub {
        font-size: 14px;
        color: var(--mcat-muted);
        margin-top: 3px;
    }
    .d-opts {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 10px;
        margin-top: 14px;
    }
    .d-opt {
        appearance: none;
        cursor: pointer;
        border: 1px solid color-mix(in srgb, var(--mcat-blue) 30%, var(--mcat-border));
        background: var(--mcat-surface);
        border-radius: 12px;
        padding: 12px 8px;
        display: flex;
        flex-direction: column;
        gap: 3px;
        align-items: center;
        transition:
            transform 0.1s ease,
            background 0.12s ease;
    }
    .d-opt:hover {
        transform: translateY(-2px);
        background: color-mix(in srgb, var(--mcat-blue) 12%, var(--mcat-surface));
    }
    .d-opt-label {
        font-weight: 700;
        font-size: 15px;
        color: var(--mcat-blue);
    }
    .d-opt-detail {
        font-size: 12px;
        color: var(--mcat-muted);
    }
    .d-done {
        display: flex;
        align-items: center;
        gap: 12px;
        text-align: left;
    }
    .d-check {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        flex: 0 0 auto;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--mcat-green);
        color: #fff;
        font-weight: 800;
    }
    @media (max-width: 520px) {
        .d-opts {
            grid-template-columns: 1fr;
        }
    }
</style>
