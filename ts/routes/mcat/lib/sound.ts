// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// Tiny, pleasant UI sounds synthesized with the Web Audio API (no audio files,
// so nothing to license or download — it works offline). Three cues:
//   click  — a soft tap on any button press
//   start  — a gentle ascending chime when a study screen opens
//   streak — a short celebratory fanfare when the daily path is finished
// A mute flag is persisted in localStorage and exposed as a Svelte store.

import { writable } from "svelte/store";

const KEY = "mcat-sound";

function readEnabled(): boolean {
    if (typeof localStorage === "undefined") {
        return true;
    }
    return localStorage.getItem(KEY) !== "0";
}

export const soundOn = writable<boolean>(readEnabled());

let enabled = readEnabled();
soundOn.subscribe((v) => {
    enabled = v;
    if (typeof localStorage !== "undefined") {
        localStorage.setItem(KEY, v ? "1" : "0");
    }
});

type AC = AudioContext;
let ctx: AC | null = null;
let master: GainNode | null = null;

function audio(): AC | null {
    if (typeof window === "undefined") {
        return null;
    }
    if (!ctx) {
        const Ctor = window.AudioContext
            ?? (window as unknown as { webkitAudioContext?: typeof AudioContext })
                .webkitAudioContext;
        if (!Ctor) {
            return null;
        }
        ctx = new Ctor();
        master = ctx.createGain();
        master.gain.value = 0.72;
        master.connect(ctx.destination);
    }
    return ctx;
}

// Resume the context from a user gesture (autoplay policy). Safe to call often.
export function unlockSound(): void {
    const ac = audio();
    if (ac && ac.state === "suspended") {
        void ac.resume();
    }
}

function note(
    ac: AC,
    freq: number,
    at: number,
    dur: number,
    peak: number,
    type: OscillatorType = "triangle",
): void {
    const osc = ac.createOscillator();
    const g = ac.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    osc.connect(g);
    g.connect(master ?? ac.destination);
    const attack = 0.008;
    g.gain.setValueAtTime(0.0001, at);
    g.gain.linearRampToValueAtTime(peak, at + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    osc.start(at);
    osc.stop(at + dur + 0.03);
}

export function playClick(): void {
    if (!enabled) {
        return;
    }
    const ac = audio();
    if (!ac) {
        return;
    }
    unlockSound();
    note(ac, 587.33, ac.currentTime, 0.055, 0.06, "sine");
}

// A gentle ascending major arpeggio; the root shifts per activity so each
// study type has its own subtle signature.
const START_ROOTS: Record<string, number> = {
    memory: 523.25, // C5
    performance: 587.33, // D5
    cars: 659.25, // E5
    diagnostic: 493.88, // B4
    mini: 587.33,
};

export function playStart(kind = "default"): void {
    if (!enabled) {
        return;
    }
    const ac = audio();
    if (!ac) {
        return;
    }
    unlockSound();
    const root = START_ROOTS[kind] ?? 523.25;
    const steps = [1, 1.25, 1.5, 2]; // root, major third, fifth, octave
    const t0 = ac.currentTime + 0.02;
    steps.forEach((r, i) => {
        note(ac, root * r, t0 + i * 0.075, i === steps.length - 1 ? 0.34 : 0.2, 0.09);
    });
}

// A short, bright fanfare for finishing the daily path / earning the streak.
export function playStreak(): void {
    if (!enabled) {
        return;
    }
    const ac = audio();
    if (!ac) {
        return;
    }
    unlockSound();
    const t0 = ac.currentTime + 0.02;
    const rise = [523.25, 659.25, 783.99, 1046.5]; // C5 E5 G5 C6
    rise.forEach((f, i) => {
        note(ac, f, t0 + i * 0.1, 0.28, 0.1);
        note(ac, f * 2, t0 + i * 0.1, 0.28, 0.025, "sine"); // shimmer octave
    });
    // Final sparkle chord.
    const end = t0 + rise.length * 0.1 + 0.02;
    [1046.5, 1318.5, 1568.0].forEach((f) => note(ac, f, end, 0.5, 0.065, "sine"));
}
