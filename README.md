# MCAT Speedrun

> **Exam: the MCAT** — scored **472–528**, four sections each **118–132**
> (Bio/Biochem, Chem/Phys, Psych/Soc, CARS).

**MCAT Speedrun** is a **desktop + iOS** study app built on a fork of
[Anki](https://apps.ankiweb.net). The two apps are one product: they share the
same cards, the same progress, and **one engine**, and they sync.

Flashcards are great at memory, but a big exam asks for more. This app measures
**three different things**, each with a range and an explicit *give-up rule* — it
never blends them into one flattering number:

- **Memory** — can you recall this fact right now? (Anki's FSRS.)
- **Performance** — can you answer a *new*, exam-style question that uses it?
- **Readiness** — what would you score today, and how sure are we? (472–528.)

The trap it refuses to hide: recalling *"mitochondria = powerhouse"* doesn't mean
you can work a cellular-respiration passage. Our own **paraphrase test** measures
that gap — students recall cards **88%** but score **40%** on reworded questions
(a **48-point gap**); Performance is not a copy of Memory.

**License:** AGPL-3.0-or-later — a fork of Anki (© Ankitects Pty Ltd); some Anki
components are BSD-3-Clause. Full credit to the Anki project.

---

## Two apps, one engine

The desktop app is the main tool; the phone app is a companion for reviewing on
the go and checking readiness. They **share the Rust engine**, not a rewrite:

```
                    ┌───────────────────────────────────┐
                    │  rslib/src/mcat_core  (Rust)        │
                    │  FSRS scheduling · scoring ·        │
                    │  replay-union event log (sync)      │
                    └───────────────────────────────────┘
                       ▲                         ▲
        Python bridge  │                         │  C FFI (ios/mcat-ffi)
                       │                         │
        ┌──────────────┴───────────┐   ┌─────────┴───────────────┐
        │ Desktop (PyQt + SvelteKit)│   │ iOS (SwiftUI)            │
        └───────────────────────────┘   └─────────────────────────┘
                       └────────── Firebase sync ──────────┘
```

Scores and scheduling are computed in the **one** Rust engine, so desktop and iOS
produce byte-identical numbers. Sync is a conflict-free **replay-union** of two
append-only event logs (see `docs/mcat-sync.md`).

---

## Install & run

### Prerequisites (macOS)

```bash
xcode-select --install                 # Xcode Command Line Tools
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"  # Homebrew
brew install just                      # task runner
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh   # Rust
# For iOS as well:
brew install xcodegen                  # + Xcode from the App Store
```

Everything else (Node, a Python venv via `uv`, protoc, ninja, …) is fetched
automatically by the build system. Then clone:

```bash
git clone https://github.com/jsonjj/mcat-speedrun.git
cd mcat-speedrun
```

### Desktop — run from source

```bash
just run          # builds Rust + Python + web, launches the app (dev mode)
```

Run `just` to list every recipe (`just check`, `just test`, `just lint`, …).

### Desktop — install the packaged app on a clean Mac

```bash
# Build a real installer (.dmg on macOS). Release build + Briefcase packaging.
RELEASE=2 ./ninja installer
# → out/installer/dist/anki-<version>-mac-apple.dmg
```

> **iCloud note:** if the repo lives on an iCloud-synced Desktop/Documents,
> Briefcase's macOS codesign can't run in place. Point the build dir outside
> iCloud once, then build:
> ```bash
> rm -rf out/installer && ln -sfn ~/Library/Caches/mcat-installer out/installer
> RELEASE=2 ./ninja installer
> ```

**To install on a clean Mac** (the build is ad-hoc signed, so Gatekeeper needs
one bypass):

1. Copy the `.dmg` to the clean machine and open it.
2. Drag **Anki** into **Applications**.
3. **Right-click Anki → Open** once (or run `xattr -cr /Applications/Anki.app`),
   then Open.
4. Launch, create an account, and start a review.

(`just wheels` also builds `pip`-installable wheels if you prefer that route.)

### iOS — build & run on a clean Simulator

```bash
bash ios/build-ffi.sh     # cross-compiles the Rust engine into an xcframework
bash ios/run-sim.sh       # xcodegen + build + install + launch on the Simulator
```

**For a clean-device run** (erase the Simulator first, then install):

```bash
xcrun simctl shutdown all
xcrun simctl erase "iPhone 17"     # pristine "device"
bash ios/run-sim.sh                # builds + installs + launches on the clean sim
```

The iOS build uses a local DerivedData path outside iCloud and the free personal
signing team baked into `ios/MCATSpeedrun/project.yml` (no paid account needed for
the Simulator).

### AI setup (optional — the app fully works and scores with AI off)

AI is **on by default** but every feature has a deterministic non-AI fallback.
Provide an OpenAI key via the env var or a gitignored file:

```bash
export OPENAI_API_KEY=sk-...
# or: echo "sk-..." > pylib/anki/mcat/.openai_key
#     echo "sk-..." > ios/MCATSpeedrun/Resources/openai_key.txt
```

With AI off (Account → toggle), the app makes **zero model calls** and still
produces all three scores.

---

## The three models

One short page each — Memory, Performance, Readiness — with formulas, ranges, and
the give-up rule, in **`docs/mcat-models.md`**. In brief:

- **Memory** = FSRS recall accuracy (recall band tightens with evidence).
- **Performance** = first-answer correctness with a **Wilson 95% interval**.
- **Readiness** = each section's performance mapped onto 118–132 (piecewise
  anchors) and summed to 472–528; the range propagates from the Wilson bounds.

**The give-up rule (honesty).** Readiness shows a full number **only when** every
section has ≥40% coverage **and** ≥2 performance sets, **and** there are ≥100
graded reviews **and** ≥40 performance attempts overall. Otherwise it **abstains**
(a standard/best-estimate diagnostic unlocks a clearly-labeled low-confidence
range). Whenever a number is shown, the app also shows the evidence, what's
missing, the calibration, the range, and the single best next action.

---

## The Rust engine change

A real change inside Anki's Rust core, not just the Python screens:

- **Mastery Query** (`rslib/src/mastery/`, `proto/anki/mastery.proto`) — a new
  backend RPC returning per-topic mastery/recall/coverage, called from Python.
- **Shared `mcat_core`** (`rslib/src/mcat_core/`) — FSRS scheduling, the three
  scores, and the replay-union sync log — shared by desktop (Python bridge) and
  iOS (C FFI, `ios/mcat-ffi`), so the engine change ships to both.

Full write-up (why Rust, upstream files touched, merge risk, tests, undo/integrity
proof): **`docs/mcat-mastery-query-note.md`**.

---

## Tests, evals & benchmarks

All re-runnable; each eval declares its pass/fail cutoff and beats a simpler
baseline. Full report with numbers and *what didn't work*: **`docs/mcat-results.md`**.

```bash
# Engine + integration tests (Rust unit tests, Python-calls-Rust, undo/integrity)
just test-rust                                   # incl. mcat_core tests
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/pytest pylib/tests/test_mcat.py

# Models & study evidence (deterministic, no key needed)
E="PYTHONPATH=pylib:out/pylib out/pyenv/bin/python tools/mcat"
$E/ablation.py          # study-feature ablation: full vs feature-off vs vanilla Anki
$E/calibration.py       # memory calibration: reliability chart + Brier / log-loss
$E/perf_eval.py         # performance model held-out accuracy + interval coverage
$E/paraphrase_test.py   # performance ≠ memory (the reworded-question gap, 7d)
$E/leakage_check.py     # scans content for leaked / near-duplicate test items
$E/benchmark.py         # one-command speed benchmark on a large deck

# AI features (need a key) — each beats a non-LLM baseline on a held-out gold set
$E/eval_reasoning.py    # reasoning grader        (100% vs 55% keyword baseline)
$E/eval_coach.py        # study coach             (100% focus vs 75% rule)
$E/eval_cars.py         # CARS debate             (grounded, engages, no capitulation)
$E/eval_injection.py    # prompt-injection resist (100%/0% leak vs 86%/14% undefended)
```

---

## Requirements → where it lives

| Requirement | Where |
| --- | --- |
| Real Rust engine change (+ 3 Rust tests + Python-calling test) | `rslib/src/mastery/`, `rslib/src/mcat_core/`, `pylib/tests/test_mcat.py`; `docs/mcat-mastery-query-note.md` |
| Two apps, one shared engine, syncing | `rslib/src/mcat_core` via Python bridge + `ios/mcat-ffi`; `docs/mcat-sync.md` |
| Three separate scores with ranges | `docs/mcat-models.md`; engine `scoring.rs` |
| Give-up rule (refuse a score without data) | `docs/mcat-models.md`; `scoring.rs` |
| Held-out, re-runnable evals + baselines | `tools/mcat/*`; `docs/mcat-results.md` |
| One study feature tested on/off (3 builds) | `tools/mcat/ablation.py`; `docs/mcat-ablation.md` |
| Memory calibration (chart + Brier/log-loss) | `tools/mcat/calibration.py`; `docs/mcat-calibration.md` |
| Performance held-out accuracy | `tools/mcat/perf_eval.py`; `docs/mcat-performance-eval.md` |
| Performance ≠ memory (paraphrase gap, 7d) | `tools/mcat/paraphrase_test.py` |
| Leakage check (7e) | `tools/mcat/leakage_check.py` |
| One-command benchmark (7h) | `tools/mcat/benchmark.py` |
| Every AI output traces to a named source | `pylib/anki/mcat/ai.py`; `docs/mcat-ai-note.md` |
| Prompt-injection resistance (hidden-text source) | `tools/mcat/eval_injection.py` |
| Runs with AI off + still scores | Account toggle; `ai_enabled` gate |
| Packaged desktop installer | `RELEASE=2 ./ninja installer` (see above) |
| Packaged phone build (clean Simulator) | `ios/run-sim.sh` (see above) |

---

## Files touched / added (the MCAT layer)

- **Rust:** `rslib/src/mastery/` (new RPC), `rslib/src/mcat_core/` (shared engine),
  `proto/anki/mastery.proto`, `ios/mcat-ffi/` (C FFI).
- **Python:** `pylib/anki/mcat/` (store, scoring, planner, content, AI, sync),
  `pylib/tests/test_mcat.py`; `qt/aqt/mcat/` (endpoints).
- **Web (desktop UI):** `ts/routes/mcat/` (SvelteKit pages + components).
- **iOS:** `ios/MCATSpeedrun/` (SwiftUI app), `ios/build-ffi.sh`, `ios/run-sim.sh`.
- **Tools & docs:** `tools/mcat/` (evals, ablation, calibration, benchmark),
  `docs/mcat-*.md`.

Upstream Anki files touched (and future-merge risk) are enumerated in
`docs/mcat-mastery-query-note.md`.

---

## Docs index

- `docs/mcat-overview.md` — architecture of the MCAT layer.
- `docs/mcat-models.md` — Memory / Performance / Readiness models + give-up rule.
- `docs/mcat-mastery-query-note.md` — the Rust change (why Rust, files, merge risk).
- `docs/mcat-results.md` — consolidated results report (every eval + what didn't work).
- `docs/mcat-ablation.md` · `docs/mcat-calibration.md` · `docs/mcat-performance-eval.md`
  — the study/model evals.
- `docs/mcat-sync.md` — conflict-free offline sync.
- `docs/mcat-ai-note.md` — AI features, source tracing, held-out evals + baselines.

---

# Anki

[![Build Status](https://github.com/ankitects/anki/actions/workflows/ci.yml/badge.svg)](https://github.com/ankitects/anki/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-dev--docs.ankiweb.net-blue)](https://dev-docs.ankiweb.net)

This repo contains the source code for the computer version of
[Anki](https://apps.ankiweb.net).

## About

Anki is a spaced repetition program. Please see the [website](https://apps.ankiweb.net) to learn more.

## Getting Started

### Contributing

Want to contribute to Anki? Check out the [Contribution Guidelines](./docs/contributing.md).

For more information on building and developing, please see [Development](./docs/development.md).

#### Contributors

The following people have contributed to Anki: [CONTRIBUTORS](./CONTRIBUTORS)

### Anki Betas

If you'd like to try development builds of Anki but don't feel comfortable
building the code, please see [Anki betas](https://betas.ankiweb.net/).

## License

Anki's license: [LICENSE](./LICENSE)
