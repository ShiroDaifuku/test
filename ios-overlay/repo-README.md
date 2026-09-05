# test

Personal iOS build workspace for MDPro3 (Unity YGOPro client) — **own code only**.

This repo hosts the *build-time iOS overlay* (source patches expressed as byte-level transforms +
new files) and the GitHub Actions workflow. It intentionally contains **no game assets, no upstream
source dumps, no credentials** — those are assembled on the runner at build time from upstream URLs.

See `ios-overlay/README.md` for the mechanism and `ios.yml` (`.github/workflows/`) for the pipeline.
Personal/private use only. Not affiliated with Konami / MyCard / MDPro3 upstream.
