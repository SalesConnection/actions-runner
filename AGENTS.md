# AGENTS.md

Guidance for AI coding agents working in this repository. Human-facing docs
live in [`README.md`](README.md); this file covers how to operate here safely.

## Project overview

This repo builds a custom **GitHub Actions self-hosted runner** Docker image.
It extends `summerwind/actions-runner:ubuntu-24.04` with:

- PHP 8.4-FPM + CLI (from the `ondrej/php` PPA) and a fixed set of extensions
- MongoDB PHP driver 2.3.3 (via `pecl`)
- Composer 2.10.2 (checksum-verified install)
- Node.js 22 (default) + 24 via nvm

The image is built multi-arch (`linux/amd64`, `linux/arm64`) and published to
Docker Hub as `jayscgi/actions-runner`. It runs under Actions Runner Controller
(ARC) on Kubernetes.

## Repo map

| Path | Role |
| --- | --- |
| `Dockerfile-v3` | **The active image.** This is the only Dockerfile CI builds. All changes go here. |
| `Dockerfile-v2` | **Deprecated.** Do not modify or use. |
| `Dockerfile` | **Deprecated (v1).** Do not modify or use. |
| `.github/workflows/docker-build.yml` | CI: builds + pushes `Dockerfile-v3` on `v*` tags. |
| `.kiro/` | Kiro IDE workspace metadata (see below). Not part of the shipped image. |

## The `.kiro/` directory

`.kiro/` holds metadata for the [Kiro](https://kiro.dev) IDE. For agents that
are not Kiro:

- `.kiro/specs/` contains structured feature specifications (requirements,
  design, tasks). If files exist there, **read them for intent and context**
  before making related changes — they describe what the maintainer is trying
  to build.
- `.kiro/steering/` (if present) holds project conventions and instructions.
- Treat `.kiro/` as documentation/configuration. **Do not delete, move, or
  restructure it**, and do not include it in the Docker build context concerns —
  it is not copied into the image.

## Conventions

- **Version pins are intentional.** PHP `8.4`, MongoDB driver `2.3.3`, Composer
  `2.10.2`, Node `22`/`24` are all pinned. Keep them explicit; do not loosen a
  pin to "latest" or bump a version unless explicitly asked.
- **Layer ordering is deliberate.** Bootstrap tools, system libraries, PHP,
  the MongoDB driver, Composer, and nvm/Node each live in their own `RUN` layer
  so a version bump in one area does not invalidate the cache for the others.
  Preserve this isolation; don't merge unrelated steps into one layer.
- **The image must end as `USER runner`.** ARC requires the container to run as
  the `runner` user. Never remove or change the final `USER runner` instruction.
- **Downloads are checksum-verified.** Composer is installed only after its
  SHA-384 is checked against the published `installer.sig`. Keep this pattern
  for any new network download; never pipe an unverified remote script into a
  shell as root.
- **Non-interactive PATH.** `/etc/environment` is set so GitHub Actions'
  non-interactive, non-login shells can resolve `node`/`npm` without sourcing
  nvm. If you change the Node setup, keep this working.

## Build & verify commands

Build the active image locally:

```bash
docker build -f Dockerfile-v3 -t actions-runner:local .
```

Multi-arch build (matches CI):

```bash
docker buildx build -f Dockerfile-v3 --platform linux/amd64,linux/arm64 -t actions-runner:local .
```

`Dockerfile-v3` self-verifies during build: the PHP layer fails the build if
`gd` lacks FreeType or JPEG support. After a successful build, confirm the
toolchain:

```bash
docker run --rm actions-runner:local bash -lc 'php -v && php -m | grep -i mongodb && composer --version && node -v'
```

> A full build pulls the base image, adds a PPA, compiles a PHP extension, and
> installs two Node versions — it is heavy and needs Docker + Buildx available.

## Release flow

Releases are **tag-driven**. Pushing a `v*` tag triggers CI to build and push
`jayscgi/actions-runner:<tag>` and `:latest`. There is no manual publish step.

## Guardrails

- **Do not publish images or push tags** yourself. Releases happen only through
  the tag-triggered CI workflow.
- **Do not edit `Dockerfile` or `Dockerfile-v2`** — they are deprecated.
- **Do not remove the final `USER runner`** instruction.
- **Do not unpin versions** or replace checksum-verified installs with
  unverified ones.
- **Secrets are not in this repo.** `DOCKER_USERNAME` / `DOCKER_PASSWORD` live
  in GitHub repo secrets. Do not hardcode credentials anywhere.

## Gotchas

- PHP 8.4 is **not** in the default Ubuntu 24.04 repos; the `ondrej/php` PPA is
  required and `software-properties-common` + `gnupg` must be installed first.
- The MongoDB extension is compiled against PHP 8.4 headers (`php8.4-dev`), so
  it must be built after PHP is installed.
- CI runs on a `self-hosted` runner — likely an instance of this very image.
