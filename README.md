# MCAT Speedrun

**Exam: the MCAT** (total 472–528; four sections each 118–132: Bio/Biochem,
Chem/Phys, Psych/Soc, and CARS).

MCAT Speedrun is a desktop + iOS study app built on a fork of
[Anki](https://apps.ankiweb.net). Both apps **share one engine** — a Rust core
(`rslib/src/mcat_core`) that does FSRS scheduling, transparent scoring, and a
replay-union event log — reached from the desktop via the Python bridge and from
iOS via a C FFI (`ios/mcat-ffi`). It measures three separate things with ranges
and an explicit give-up rule: **Memory** (recall), **Performance** (new
exam-style questions), and **Readiness** (a 472–528 projection).

**License:** AGPL-3.0-or-later, a fork of Anki (© Ankitects Pty Ltd); some parts
of Anki are BSD-3-Clause. Credit to the Anki project.

### Key docs

- `docs/mcat-overview.md` — architecture overview of the MCAT layer.
- `docs/mcat-mastery-query-note.md` — the Rust engine change (why Rust, files
  touched, merge risk) + the shared `mcat_core` engine.
- `docs/mcat-ai-note.md` — the AI features, source tracing, held-out eval +
  baseline, and the give-up rule.

### Build & run

- **Desktop:** `just run` (builds Rust + Python + web, launches the app).
  Tests: `cargo test -p anki mcat_core` and
  `PYTHONPATH="pylib:out/pylib" out/pyenv/bin/pytest pylib/tests/test_mcat.py`.
  Installer wheels: `just wheels` (verified installable in a clean venv).
- **iOS:** `bash ios/build-ffi.sh` (builds the shared engine into an
  xcframework), then `bash ios/run-sim.sh` (builds + launches on the Simulator).
- **AI:** on by default, same three features on desktop + iOS (reasoning
  feedback, CARS debate, study coach), each grounded in a named source. The key
  is read from `OPENAI_API_KEY` or a gitignored file (desktop
  `pylib/anki/mcat/.openai_key`, iOS `ios/MCATSpeedrun/Resources/openai_key.txt`).
- **AI evals** (held-out, each beats a baseline; key from env or the file):
  `PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/eval_reasoning.py`
  (and `eval_coach.py`, `eval_cars.py`). See `docs/mcat-ai-note.md`.
- **Give-up rule:** Readiness shows no number unless all four sections have ≥40%
  coverage and ≥2 performance sets, plus ≥100 graded reviews and ≥40 performance
  attempts overall; otherwise it abstains (a broad diagnostic unlocks a labeled
  low-confidence range). AI is on by default and fully toggleable; with AI off,
  the app makes zero model calls and still produces all three scores.

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
