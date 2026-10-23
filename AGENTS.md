# AGENTS.md

Guidance for AI coding agents working in this repository. Human-facing docs
live in [`README.md`](README.md); this file covers how to operate here safely.

## Project overview

This repo builds a custom **GitHub Actions self-hosted runner** Docker image in
**two active lines** that ship side by side:

- **v3 — PHP 8.4** (`Dockerfile-v3`)
- **v4 — PHP 8.5** (`Dockerfile-v4`)

Both lines extend the same base image and share an identical seven-layer
structure; they differ only in the PHP line and the one dependency gated on it
(the MongoDB PHP extension). Everything else — base image, system libraries,
Composer, and Node/nvm — is identical between them.

Shared across both lines:

- Base `summerwind/actions-runner:ubuntu-24.04`
- Composer 2.10.2 (checksum-verified install)
- Node.js 22 (default) + 24 via nvm

Per line:

| Line | Dockerfile | PHP | MongoDB PHP extension |
| --- | --- | --- | --- |
| v3 | `Dockerfile-v3` | 8.4-FPM + CLI (from `ondrej/php` PPA) | 2.3.3 |
| v4 | `Dockerfile-v4` | 8.5-FPM + CLI (from `ondrej/php` PPA) | 2.5.5 |

Each line is built multi-arch (`linux/amd64`, `linux/arm64`) and published to
Docker Hub as `jayscgi/actions-runner`. The images run under Actions Runner
Controller (ARC) on Kubernetes.

## Repo map

| Path | Role |
| --- | --- |
| `Dockerfile-v3` | **Active — PHP 8.4.** One of the two images CI builds. |
| `Dockerfile-v4` | **Active — PHP 8.5.** One of the two images CI builds. |
| `Dockerfile-v2` | **Deprecated.** Do not modify or use. |
| `Dockerfile` | **Deprecated (v1).** Do not modify or use. |
| `.github/workflows/docker-build.yml` | CI: on a `v*` tag, builds + pushes **v3 or v4**, selected by the tag suffix (see Release flow). |
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

- **Version pins are intentional.** Keep them explicit; do not loosen a pin to
  "latest" or bump a version unless explicitly asked.
  - **Shared pins** (identical in v3 and v4): base
    `summerwind/actions-runner:ubuntu-24.04`, Composer `2.10.2`, Node `22`/`24`.
  - **Per-line pins:** v3 → PHP `8.4`, MongoDB extension `2.3.3`; v4 → PHP
    `8.5`, MongoDB extension `2.5.5`. The MongoDB pin tracks the PHP line (2.3.3
    predates PHP 8.5 support; 2.5.x adds it), so bump it only together with its
    PHP line.
- **Layer ordering is deliberate.** In both Dockerfiles, bootstrap tools,
  system libraries, PHP, the MongoDB extension, Composer, and nvm/Node each live
  in their own `RUN` layer so a version bump in one area does not invalidate the
  cache for the others. Preserve this isolation; don't merge unrelated steps
  into one layer.
- **Both images must end as `USER runner`.** ARC requires the container to run
  as the `runner` user. Never remove or change the final `USER runner`
  instruction in either Dockerfile.
- **Downloads are checksum-verified.** Composer is installed only after its
  SHA-384 is checked against the published `installer.sig`. Keep this pattern
  for any new network download; never pipe an unverified remote script into a
  shell as root.
- **Non-interactive PATH.** `/etc/environment` is set so GitHub Actions'
  non-interactive, non-login shells can resolve `node`/`npm` without sourcing
  nvm. If you change the Node setup in either image, keep this working.

## Build & verify commands

Build each line locally (single-arch, matches your host):

```bash
# v3 — PHP 8.4
docker build -f Dockerfile-v3 -t actions-runner:local .

# v4 — PHP 8.5
docker build -f Dockerfile-v4 -t actions-runner-v4:local .
```

Multi-arch build (matches CI):

```bash
# v3 — PHP 8.4
docker buildx build -f Dockerfile-v3 --platform linux/amd64,linux/arm64 -t actions-runner:local .

# v4 — PHP 8.5
docker buildx build -f Dockerfile-v4 --platform linux/amd64,linux/arm64 -t actions-runner-v4:local .
```

Both Dockerfiles self-verify during build: the PHP layer fails the build if
`gd` lacks FreeType or JPEG support. After a successful build, confirm the
toolchain for each image:

```bash
# v3 — expect PHP 8.4
docker run --rm actions-runner:local bash -lc 'php -v && php -m | grep -i mongodb && composer --version && node -v'

# v4 — expect PHP 8.5
docker run --rm actions-runner-v4:local bash -lc 'php -v && php -m | grep -i mongodb && composer --version && node -v'
```

> Note: the base image's `ENTRYPOINT` is `["/bin/bash","-c"]`, so a bare
> `docker run --rm <img> bash -lc '...'` can silently no-op. If a smoke check
> produces no output, override the entrypoint:
> `docker run --rm --entrypoint bash <img> -lc '...'`.

> A full build pulls the base image, adds a PPA, compiles a PHP extension, and
> installs two Node versions — it is heavy and needs Docker + Buildx available.

## Release flow

Releases are **tag-driven**, and the PHP line is selected from the git tag
suffix. There is no manual publish step and no manual line selector.

| Git tag pushed | Line built | Image tags published |
| --- | --- | --- |
| `v*` (no suffix, e.g. `v1.2.3`) | v3 / PHP 8.4 from `Dockerfile-v3` | `jayscgi/actions-runner:<tag>` and `:latest` |
| `v*-php8.5` (e.g. `v1.2.3-php8.5`) | v4 / PHP 8.5 from `Dockerfile-v4` | `jayscgi/actions-runner:<tag>` (already ends in `-php8.5`) and `:php8.5-latest` |

Exactly one line is published per tag push. The v4 tags never overwrite the v3
`:<tag>` or `:latest`, so existing consumers are not disrupted.

## Guardrails

- **Do not publish images or push tags** yourself. Releases happen only through
  the tag-triggered CI workflow.
- **Do not edit `Dockerfile` or `Dockerfile-v2`** — they are deprecated.
  (`Dockerfile-v3` and `Dockerfile-v4` are both active — neither is deprecated.)
- **Do not remove the final `USER runner`** instruction in either image.
- **Do not unpin versions** or replace checksum-verified installs with
  unverified ones.
- **Secrets are not in this repo.** `DOCKER_USERNAME` / `DOCKER_PASSWORD` live
  in GitHub repo secrets. Do not hardcode credentials anywhere.

## Gotchas

- The target PHP version (8.4 for v3, 8.5 for v4) is **not** in the default
  Ubuntu 24.04 repos; the `ondrej/php` PPA is required for both, and
  `software-properties-common` + `gnupg` must be installed first.
- The MongoDB extension is compiled against the matching PHP headers — v3 builds
  against `php8.4-dev`, v4 against `php8.5-dev` — so it must be built after PHP
  is installed in each image.
- CI runs on a `self-hosted` runner — likely an instance of one of these images.
