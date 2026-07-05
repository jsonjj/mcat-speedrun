<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

The primary "what to do next" call to action, as an engaging square card with a
pulsing orb and twinkling sparkles that invite a tap. Adapts to the day's state
(take diagnostic / start·continue path / do extra practice).
-->
<script lang="ts">
    import Icon from "./Icon.svelte";

    export let eyebrow: string;
    export let title: string;
    export let sub: string;
    export let icon: string;
    export let href: string;
    export let green = false;
    export let done = false;
    export let progress: number | null = null;
</script>

<a class="csq" class:green {href}>
    <div class="csq-eyebrow">
        <span>{eyebrow}</span>
        {#if done}<span class="csq-check">✓</span>{/if}
    </div>

    <div class="csq-center">
        <span class="star s1">✦</span>
        <span class="star s2">✦</span>
        <span class="star s3">✦</span>
        <span class="star s4">✦</span>
        <div class="csq-orb">
            <span class="csq-ring"></span>
            <span class="csq-ring csq-ring2"></span>
            <Icon name={icon} size={36} />
        </div>
    </div>

    <div class="csq-foot">
        <div class="csq-title">{title}</div>
        <div class="csq-sub">{sub}</div>
        {#if progress != null}
            <div class="csq-track">
                <div class="csq-fill" style={`width:${progress * 100}%`}></div>
            </div>
        {/if}
    </div>

    <div class="csq-arrow"><Icon name="arrow" size={20} /></div>
</a>

<style lang="scss">
    .csq {
        position: relative;
        display: flex;
        flex-direction: column;
        text-decoration: none;
        color: #fff;
        border-radius: 24px;
        padding: 22px 24px;
        aspect-ratio: 1.25 / 1;
        min-height: 230px;
        max-height: 290px;
        overflow: hidden;
        background: linear-gradient(150deg, var(--mcat-accent), var(--mcat-accent-2));
        box-shadow: 0 20px 44px -20px
            color-mix(in srgb, var(--mcat-accent) 75%, transparent);
        transition:
            transform 0.16s ease,
            box-shadow 0.16s ease;
        animation: csq-breathe 4.5s ease-in-out infinite;
    }
    .csq.green {
        background: linear-gradient(150deg, var(--mcat-green), #10b981);
        box-shadow: 0 20px 44px -20px
            color-mix(in srgb, var(--mcat-green) 75%, transparent);
    }
    .csq:hover {
        transform: translateY(-4px) scale(1.008);
        box-shadow: 0 26px 54px -18px
            color-mix(in srgb, var(--mcat-accent) 70%, transparent);
    }
    .csq.green:hover {
        box-shadow: 0 26px 54px -18px
            color-mix(in srgb, var(--mcat-green) 70%, transparent);
    }
    @keyframes csq-breathe {
        0%,
        100% {
            box-shadow: 0 20px 44px -20px
                color-mix(in srgb, var(--mcat-accent) 75%, transparent);
        }
        50% {
            box-shadow: 0 24px 52px -18px
                color-mix(in srgb, var(--mcat-accent) 85%, transparent);
        }
    }

    .csq-eyebrow {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 12px;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        opacity: 0.94;
    }
    .csq-check {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 17px;
        height: 17px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.28);
        font-size: 11px;
    }

    /* Pulsing orb + expanding rings */
    .csq-center {
        position: relative;
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    .csq-orb {
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 92px;
        height: 92px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.2);
        animation: csq-orb 2.6s ease-in-out infinite;
    }
    .csq-ring {
        position: absolute;
        inset: 0;
        border-radius: 50%;
        border: 2px solid rgba(255, 255, 255, 0.55);
        animation: csq-ring 2.6s ease-out infinite;
    }
    .csq-ring2 {
        animation-delay: 1.3s;
    }
    @keyframes csq-orb {
        0%,
        100% {
            transform: scale(1);
        }
        50% {
            transform: scale(1.07);
        }
    }
    @keyframes csq-ring {
        0% {
            transform: scale(1);
            opacity: 0.6;
        }
        70% {
            opacity: 0;
        }
        100% {
            transform: scale(1.55);
            opacity: 0;
        }
    }

    /* Twinkling sparkles */
    .star {
        position: absolute;
        color: rgba(255, 255, 255, 0.9);
        animation: csq-twinkle 3s ease-in-out infinite;
        pointer-events: none;
    }
    .s1 {
        top: 8%;
        left: 30%;
        font-size: 13px;
        animation-delay: 0s;
    }
    .s2 {
        top: 22%;
        right: 24%;
        font-size: 17px;
        animation-delay: 0.7s;
    }
    .s3 {
        bottom: 14%;
        left: 24%;
        font-size: 12px;
        animation-delay: 1.3s;
    }
    .s4 {
        top: 42%;
        right: 16%;
        font-size: 10px;
        animation-delay: 2s;
    }
    @keyframes csq-twinkle {
        0%,
        100% {
            opacity: 0.2;
            transform: scale(0.75);
        }
        50% {
            opacity: 1;
            transform: scale(1.15);
        }
    }

    .csq-foot {
        padding-right: 46px;
    }
    .csq-title {
        font-size: 25px;
        font-weight: 800;
        letter-spacing: -0.01em;
        line-height: 1.1;
    }
    .csq-sub {
        font-size: 14px;
        font-weight: 600;
        opacity: 0.92;
        margin-top: 4px;
    }
    .csq-track {
        margin-top: 12px;
        height: 7px;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.28);
        overflow: hidden;
    }
    .csq-fill {
        height: 100%;
        border-radius: 999px;
        background: #fff;
    }

    .csq-arrow {
        position: absolute;
        right: 20px;
        bottom: 20px;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 40px;
        height: 40px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.2);
        transition: background 0.14s ease;
    }
    .csq:hover .csq-arrow {
        background: rgba(255, 255, 255, 0.34);
    }

    @media (prefers-reduced-motion: reduce) {
        .csq,
        .csq-orb,
        .csq-ring,
        .star {
            animation: none;
        }
    }
</style>
