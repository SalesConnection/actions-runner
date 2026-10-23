---
inclusion: fileMatch
fileMatchPattern: '**/Dockerfile*'
---

# Building the runner image

Build guidance for the custom GitHub Actions self-hosted runner image. This
loads automatically when working on a Dockerfile or the build workflow.

## Scope

- Build **`Dockerfile-v3` only**. It is the active image and the only one CI
  builds.
- `Dockerfile` (v1) and `Dockerfile-v2` are **deprecated** — do not build,
  edit, or reference them.

Reference: #[[file:Dockerfile-v3]]

## Local build

Single-arch (matches your host):

```bash
docker build -f Dockerfile-v3 -t actions-runner:local .
```

Multi-arch with Buildx (matches CI):

```bash
docker buildx build \
  -f Dockerfile-v3 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner:local .
```

> A full build is heavy: it pulls the Ubuntu 24.04 base, adds the `ondrej/php`
> PPA, compiles the MongoDB PHP extension, and installs two Node versions. It
> needs Docker + Buildx available and can take a while on a cold cache.

## Layer-caching discipline

Each concern lives in its own `RUN` layer, in this order:

1. Bootstrap (`gnupg`, `software-properties-common`)
2. `ondrej/php` PPA
3. System libraries
4. PHP 8.4 + extensions
5. MongoDB PHP driver (`pecl`)
6. Composer
7. nvm + Node 22/24

Keep this isolation. **Do not merge unrelated steps into one layer** — it is
deliberate so a bump in one area (e.g. the MongoDB driver) does not invalidate
the cache for everything after it. When adding a step, place it so it
invalidates the minimum downstream.

## Build-time verification (already in the Dockerfile)

- The **PHP layer fails the build** if `gd` lacks FreeType or JPEG support.
  Keep that check.
- **Composer is checksum-verified**: its SHA-384 is compared against the
  published `installer.sig` before the installer runs. Preserve this pattern
  for any new network download — never pipe an unverified remote script into a
  shell as root.

## Hard constraints

- The image **must end as `USER runner`** — ARC requires it. Never remove or
  change the final `USER runner` instruction.
- **Keep version pins**: PHP `8.4`, MongoDB driver `2.3.3`, Composer `2.10.2`,
  Node `22`/`24`. Do not loosen to "latest" or bump unless explicitly asked.
- **Preserve the `/etc/environment` PATH entry** for Node 22 so GitHub Actions'
  non-interactive, non-login shells resolve `node`/`npm` without sourcing nvm.

## CI build parity

Defined in `.github/workflows/docker-build.yml`:

- **Trigger:** push of a `v*` tag
- **Runner:** `self-hosted`
- **Build:** `Dockerfile-v3`, multi-arch (`linux/amd64`, `linux/arm64`)
- **Push:** `jayscgi/actions-runner:<tag>` and `:latest`
- **Secrets:** `DOCKER_USERNAME`, `DOCKER_PASSWORD` (GitHub repo secrets)

Do **not** push tags or publish images as part of a build — publishing happens
only through the tag-triggered workflow.

## Post-build smoke check

After a successful build, confirm the toolchain:

```bash
docker run --rm actions-runner:local bash -lc '
  php -v
  php -m | grep -i mongodb
  composer --version
  node -v
'
```

Expected: PHP 8.4, `mongodb` present, Composer 2.10.2, Node 22 active.
