---
inclusion: fileMatch
fileMatchPattern: '**/Dockerfile*'
---

# Building the runner image

Build guidance for the custom GitHub Actions self-hosted runner image. This
loads automatically when working on a Dockerfile or the build workflow.

## Scope

- **`Dockerfile-v3` (PHP 8.4) and `Dockerfile-v4` (PHP 8.5) are both active**
  and both buildable. They share one base image and an identical seven-layer
  structure, differing only in the PHP line and the MongoDB extension gated on
  it.
- `Dockerfile` (v1) and `Dockerfile-v2` are **deprecated** — do not build,
  edit, or reference them.

References: #[[file:Dockerfile-v3]] #[[file:Dockerfile-v4]]

## Local build

Single-arch (matches your host):

```bash
# v3 — PHP 8.4
docker build -f Dockerfile-v3 -t actions-runner:local .

# v4 — PHP 8.5
docker build -f Dockerfile-v4 -t actions-runner-v4:local .
```

Multi-arch with Buildx (matches CI):

```bash
# v3 — PHP 8.4
docker buildx build \
  -f Dockerfile-v3 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner:local .

# v4 — PHP 8.5
docker buildx build \
  -f Dockerfile-v4 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner-v4:local .
```

> A full build is heavy: it pulls the Ubuntu 24.04 base, adds the `ondrej/php`
> PPA, compiles the MongoDB PHP extension, and installs two Node versions. It
> needs Docker + Buildx available and can take a while on a cold cache.

## Layer-caching discipline

Each concern lives in its own `RUN` layer, in this order (identical in both
images):

1. Bootstrap (`gnupg`, `software-properties-common`)
2. `ondrej/php` PPA
3. System libraries
4. PHP 8.4 (v3) / 8.5 (v4) + extensions
5. MongoDB PHP extension via `pecl` (2.3.3 v3 / 2.5.5 v4)
6. Composer
7. nvm + Node 22/24

Keep this isolation. **Do not merge unrelated steps into one layer** — it is
deliberate so a bump in one area (e.g. the MongoDB extension) does not
invalidate the cache for everything after it. When adding a step, place it so it
invalidates the minimum downstream.

## Build-time verification (already in the Dockerfiles)

- The **PHP layer fails the build** if `gd` lacks FreeType or JPEG support, in
  both images. Keep that check.
- **Composer is checksum-verified**: its SHA-384 is compared against the
  published `installer.sig` before the installer runs. Preserve this pattern
  for any new network download — never pipe an unverified remote script into a
  shell as root.

## Hard constraints

- Both images **must end as `USER runner`** — ARC requires it. Never remove or
  change the final `USER runner` instruction in either Dockerfile.
- **Keep version pins.** Do not loosen to "latest" or bump unless explicitly
  asked.
  - **Shared** (identical in v3 and v4): Composer `2.10.2`, Node `22`/`24`,
    base `summerwind/actions-runner:ubuntu-24.04`.
  - **Per line:** v3 → PHP `8.4`, MongoDB extension `2.3.3`; v4 → PHP `8.5`,
    MongoDB extension `2.5.5`. The MongoDB pin tracks its PHP line.
- **Preserve the `/etc/environment` PATH entry** for Node 22 in both images so
  GitHub Actions' non-interactive, non-login shells resolve `node`/`npm` without
  sourcing nvm.

## CI build parity

Defined in `.github/workflows/docker-build.yml`:

- **Trigger:** push of a `v*` tag
- **Runner:** `self-hosted`
- **Line selection:** chosen from the tag suffix — a tag ending in `-php8.5`
  builds v4; any other `v*` tag builds v3. Exactly one line is built per push.
- **Build:** `Dockerfile-v3` or `Dockerfile-v4`, multi-arch (`linux/amd64`,
  `linux/arm64`)
- **Push:**
  - v3 (`v*`, no suffix): `jayscgi/actions-runner:<tag>` and `:latest`
  - v4 (`v*-php8.5`): `jayscgi/actions-runner:<tag>` (already carries the
    `-php8.5` suffix) and `:php8.5-latest`
- **Secrets:** `DOCKER_USERNAME`, `DOCKER_PASSWORD` (GitHub repo secrets)

The v4 tags never overwrite the v3 `:<tag>` or `:latest`. Do **not** push tags
or publish images as part of a build — publishing happens only through the
tag-triggered workflow.

## Post-build smoke check

After a successful build, confirm the toolchain for whichever image you built:

```bash
# v3 — expect PHP 8.4
docker run --rm actions-runner:local bash -lc '
  php -v
  php -m | grep -i mongodb
  composer --version
  node -v
'

# v4 — expect PHP 8.5
docker run --rm actions-runner-v4:local bash -lc '
  php -v
  php -m | grep -i mongodb
  composer --version
  node -v
'
```

Expected v3: PHP 8.4, `mongodb` present, Composer 2.10.2, Node 22 active.
Expected v4: PHP 8.5, `mongodb` present, Composer 2.10.2, Node 22 active.

> Note: the base image's `ENTRYPOINT` is `["/bin/bash","-c"]`, so a bare
> `docker run --rm <img> bash -lc '...'` can silently no-op. If the smoke check
> produces no output, override the entrypoint:
> `docker run --rm --entrypoint bash <img> -lc '...'`.
