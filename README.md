# HeartThreshold

Personal wellness app for Apple Watch and iPhone. Start a heart-rate session on the watch, get haptic warnings before and at a target you set, and review the finished recording on the phone.

The watch decides alerts and records every heart-rate sample. The phone is not needed while a session is running. This is a personal wellness tool, not diagnosis or emergency monitoring.

## Status

Docs and branch workflows are in place. The next build step is Phase 1: shared contracts, threshold and summary logic, and report grouping. No app code yet.

## Docs

- [Architecture](docs/ARCHITECTURE.md) — what to build and the rules it must follow
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md) — phase order and checkpoints

## Branches

Work lands on feature branches, which open a pull request into `develop`. Pushes to `develop` open a pull request into `main`.
