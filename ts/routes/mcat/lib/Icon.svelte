<!--
Copyright: Ankitects Pty Ltd and contributors
License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

Small inline stroke-icon set (no external dependency). Uses currentColor.
-->
<script lang="ts">
    export let name: string;
    export let size = 22;

    const ICONS: Record<string, string> = {
        brain: '<path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-1 5.8A3 3 0 0 0 8 17a3 3 0 0 0 4 1 3 3 0 0 0 4-1 3 3 0 0 0 3-4.2A3 3 0 0 0 18 7a3 3 0 0 0-3-3 3 3 0 0 0-3 1 3 3 0 0 0-3-1z"/><path d="M12 5.5v12"/>',
        target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/>',
        gauge: '<path d="M3.5 16a9 9 0 1 1 17 0"/><path d="M12 13l4-4"/><circle cx="12" cy="13" r="1.2" fill="currentColor" stroke="none"/>',
        book: '<path d="M12 6c-1.6-1-4-1.5-6-1.5S3 5 3 5v13s1-.5 3-.5 4.4.5 6 1.5"/><path d="M12 6c1.6-1 4-1.5 6-1.5S21 5 21 5v13s-1-.5-3-.5-4.4.5-6 1.5"/><path d="M12 6v13"/>',
        flask: '<path d="M9 3h6"/><path d="M10 3v6l-5 9a2 2 0 0 0 1.8 3h10.4a2 2 0 0 0 1.8-3l-5-9V3"/><path d="M7 15h10"/>',
        atom: '<circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><ellipse cx="12" cy="12" rx="9" ry="4"/><ellipse cx="12" cy="12" rx="9" ry="4" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="9" ry="4" transform="rotate(120 12 12)"/>',
        smiley: '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0"/><circle cx="9" cy="10" r=".7" fill="currentColor" stroke="none"/><circle cx="15" cy="10" r=".7" fill="currentColor" stroke="none"/>',
        sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
        moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
        check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
        lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
        flag: '<path d="M5 21V4"/><path d="M5 4.5h11l-1.6 3L16 10.5H5"/>',
        spark: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/>',
        arrow: '<path d="M5 12h14"/><path d="M13 6l6 6-6 6"/>',
        sound: '<path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16 8.5a4 4 0 0 1 0 7"/><path d="M18.7 6a7 7 0 0 1 0 12"/>',
        mute: '<path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16.5 9.5l5 5M21.5 9.5l-5 5"/>',
    };

    $: inner = ICONS[name] ?? "";
</script>

<svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
>
    {@html inner}
</svg>
