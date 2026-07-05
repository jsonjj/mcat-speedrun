<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Renders MCAT content (questions, choices, explanations, flashcards) as markdown
— bold, GFM tables, paragraphs — with responsive tables (scroll on narrow
screens). Source is HTML-escaped in renderContent, so {@html} is safe here.
-->
<script lang="ts">
    import { renderContent } from "./markdown";

    export let text: string | null | undefined = "";
    export let inline = false;
</script>

{#if inline}
    <!-- eslint-disable-next-line svelte/no-at-html-tags -->
    <span class="mcat-md mcat-md-inline">{@html renderContent(text)}</span>
{:else}
    <!-- eslint-disable-next-line svelte/no-at-html-tags -->
    <div class="mcat-md">{@html renderContent(text)}</div>
{/if}
