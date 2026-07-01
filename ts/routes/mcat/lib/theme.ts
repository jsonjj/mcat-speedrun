// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// Self-controlled light/dark theme for the MCAT app, toggled from the dashboard.
// Persisted per-device in localStorage and applied as a `.dark` class on the app
// root by the layout.

import { writable } from "svelte/store";

const KEY = "mcat-dark-mode";

function read(): boolean {
    if (typeof localStorage === "undefined") {
        return false;
    }
    return localStorage.getItem(KEY) === "1";
}

export const darkMode = writable<boolean>(read());

darkMode.subscribe((value) => {
    if (typeof localStorage !== "undefined") {
        localStorage.setItem(KEY, value ? "1" : "0");
    }
});
