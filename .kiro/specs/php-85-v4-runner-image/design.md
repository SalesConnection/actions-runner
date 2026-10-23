# Design: PHP 8.5 Support via a New `Dockerfile-v4`

## Overview

This design adds a PHP 8.5 runner image as a new `Dockerfile-v4` that lives
alongside the unchanged PHP 8.4 `Dockerfile-v3`. `Dockerfile-v4` is a near-copy
of v3: it keeps the same base image, the same seven-layer structure, the same
system libraries, Composer pin, and Node/nvm setup. Only the PHP line (8.4 →
8.5) and the one dependency gated on it (the MongoDB PHP extension, 2.3.3 →
2.5.5) change.

The CI workflow is extended from building one Dockerfile to building both, with
non-colliding Docker Hub tags so v3 consumers are never disrupted.

### Why a new file instead of editing v3

Editing v3 in place would force every consumer of `jayscgi/actions-runner:latest`
onto PHP 8.5 at once. A separate v4, published to its own tags, lets teams
migrate on their own schedule and lets v3 keep receiving the PHP 8.4 line. This
matches the repo's existing versioned-Dockerfile convention.

## Architecture

### File layout after this change

```
Dockerfile          # v1, deprecated — untouched
Dockerfile-v2       # deprecated — untouched
Dockerfile-v3       # PHP 8.4, ACTIVE — untouched
Dockerfile-v4       # PHP 8.5, ACTIVE — NEW
.github/workflows/docker-build.yml   # builds BOTH v3 and v4
```

### `Dockerfile-v4` layer plan (mirrors v3)

| # | Layer | Change vs v3 |
| - | ----- | ------------ |
| 0 | `FROM summerwind/actions-runner:ubuntu-24.04` + `ENV` | none |
| 1 | Bootstrap: `gnupg`, `software-properties-common` | none |
| 2 | `ppa:ondrej/php` + `apt-get update` | none (same PPA serves PHP 8.5) |
| 3 | System libraries (incl. `openssh-client`) | none |
| 4 | PHP **8.5** + extensions + `gd` verification | `php8.4-*` → `php8.5-*`; `phpenmod -v 8.4` → `-v 8.5` |
| 5 | MongoDB extension via `pecl` | `mongodb-2.3.3` → `mongodb-2.5.5`; `/etc/php/8.4/...` → `/etc/php/8.5/...`; `phpenmod -v 8.4` → `-v 8.5` |
| 6 | Composer `2.10.2` (checksum-verified) | none |
| 7 | nvm + Node 22/24 + `/etc/environment` PATH | none |
| 8 | `USER runner` | none |

Layers 0–3, 6, 7, and 8 are byte-for-byte identical to v3. All PHP-8.5-specific
change is confined to layers 4 and 5.

## Components and Interfaces

### Component 1: `Dockerfile-v4` — PHP 8.5 layer (layer 4)

Derived from v3's PHP layer with every `8.4` token replaced by `8.5`:

```dockerfile
# ── PHP 8.5-FPM + extensions ───────────────────────────────────────────────────
# php8.5-dev     — PHP headers required by pecl to compile the MongoDB extension.
# php-pear       — provides the pecl command.
# php8.5-gd      — built by ondrej/php with --with-freetype and --with-jpeg.
# php8.5-sqlite3 — provides sqlite3, pdo, and pdo_sqlite extensions.
# Verification step fails the build if gd lacks FreeType or JPEG support.
RUN sudo apt-get update -yq && \
    sudo apt-get install -yq --no-install-recommends \
        php8.5 \
        php8.5-fpm \
        php8.5-cli \
        php8.5-dev \
        php8.5-bcmath \
        php8.5-curl \
        php8.5-exif \
        php8.5-gd \
        php8.5-mbstring \
        php8.5-xml \
        php8.5-zip \
        php8.5-intl \
        php8.5-gmp \
        php8.5-soap \
        php8.5-sqlite3 \
        php8.5-redis \
        php-pear && \
    php -r "phpinfo();" | grep -i "freetype" > /dev/null && \
    php -r "phpinfo();" | grep -i "jpeg" > /dev/null && \
    sudo phpenmod -v 8.5 bcmath curl exif gd intl mbstring gmp redis soap sqlite3 xml zip && \
    sudo rm -rf /var/lib/apt/lists/*
```

Note: because only PHP 8.5 is installed in this image, the `php` CLI on `PATH`
resolves to 8.5, so the `php -r "phpinfo();"` gd checks exercise the 8.5 build.

### Component 2: `Dockerfile-v4` — MongoDB extension layer (layer 5)

```dockerfile
# ── MongoDB PHP extension 2.5.5 (via pecl) ─────────────────────────────────────
# 2.5.x is the MongoDB extension line that supports PHP 8.5; 2.3.3 (used by v3)
# predates PHP 8.5 support. Compiled against the PHP 8.5 headers installed above.
RUN sudo pecl install mongodb-2.5.5 && \
    echo "extension=mongodb.so" | sudo tee /etc/php/8.5/mods-available/mongodb.ini > /dev/null && \
    sudo phpenmod -v 8.5 mongodb
```

### Component 3: CI workflow — select the line from the git tag

The workflow stays tag-driven (`on: push: tags: ['v*']`) with no manual input.
The PHP line is chosen from the tag name: a tag ending in `-php8.5` builds v4,
any other `v*` tag builds v3. Because GitHub's `on.push.tags` glob cannot branch
to different jobs by sub-pattern, the split is done inside one job with two
`docker/build-push-action` steps guarded by a step-level `if:` on
`github.ref_name`. Both steps reuse the single QEMU + Buildx + Docker Hub login
setup. Exactly one of the two steps runs per tag push.

```yaml
on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: self-hosted
    steps:
      # checkout, QEMU, Buildx, Docker Hub login — shared, unchanged

    - name: Build and push Docker image (v3 — PHP 8.4)
      if: ${{ !endsWith(github.ref_name, '-php8.5') }}
      uses: docker/build-push-action@v5
      with:
        context: .
        file: Dockerfile-v3
        platforms: linux/amd64,linux/arm64
        push: true
        tags: jayscgi/actions-runner:${{ github.ref_name }},jayscgi/actions-runner:latest
        labels: jayscgi/actions-runner:${{ github.ref_name }}

    - name: Build and push Docker image (v4 — PHP 8.5)
      if: ${{ endsWith(github.ref_name, '-php8.5') }}
      uses: docker/build-push-action@v5
      with:
        context: .
        file: Dockerfile-v4
        platforms: linux/amd64,linux/arm64
        push: true
        tags: jayscgi/actions-runner:${{ github.ref_name }},jayscgi/actions-runner:php8.5-latest
        labels: jayscgi/actions-runner:${{ github.ref_name }}
```

#### Tag convention and image tagging (design decision)

Git tag → line → published image tags:

| Git tag pushed | Line | Image tags published |
| --- | --- | --- |
| `v1.2.3` (no suffix) | v3 / PHP 8.4 | `jayscgi/actions-runner:v1.2.3`, `jayscgi/actions-runner:latest` |
| `v1.2.3-php8.5` | v4 / PHP 8.5 | `jayscgi/actions-runner:v1.2.3-php8.5`, `jayscgi/actions-runner:php8.5-latest` |

v3 keeps `:<tag>` and `:latest` exactly as today — no regression for existing
consumers. v4 publishes the git tag verbatim as its image tag (already carrying
the `-php8.5` suffix) plus a `:php8.5-latest` moving tag, all on the same
`jayscgi/actions-runner` repo. Because the v4 git tag already ends in `-php8.5`,
its image tag cannot collide with a v3 `:<tag>` or with `:latest`.

Rationale: selecting from the tag suffix needs no workflow input and keeps every
publish a single `git push` of one tag. Suffix-on-same-repo avoids a second
Docker Hub repository and keeps both lines discoverable together. Alternatives —
a `workflow_dispatch` choice input, or a separate `jayscgi/actions-runner-php85`
repo — were rejected: the input adds a manual step the maintainer does not want,
and a second repo adds repo-management overhead for no clear benefit.

> **Decided:** the `-php8.5` git-tag suffix and the `:php8.5-latest` moving tag
> on the same `jayscgi/actions-runner` repo (see Resolved decisions). A
> different suffix or a separate repo is not adopted; changing it later would
> touch only the trigger pattern match and the `tags:` lines.
>
> **Edge case:** a tag ending in `-php8.5` is the only thing that routes to v4.
> If a future third line is added, the `else`-style "any other `v*`" fallback
> for v3 must be revisited so a new suffix is not silently built as v3.

### Component 4: Documentation updates

`AGENTS.md` and `.kiro/steering/` currently assert "build `Dockerfile-v3` only"
and describe v3 as the single active image. After v4 exists, the documentation
gets a **full rewrite** so it describes a two-active-image repo end to end,
rather than a minimal "both active" note. `Dockerfile` and `Dockerfile-v2`
remain deprecated throughout.

- `AGENTS.md` — rewrite every section that assumes a single active image:
  - **Project overview**: state the repo builds two active runner images — v3
    (PHP 8.4) and v4 (PHP 8.5) — sharing one base and structure, differing only
    in the PHP line and the MongoDB extension gated on it.
  - **Repo map**: `Dockerfile-v3` = active PHP 8.4; `Dockerfile-v4` = active
    PHP 8.5; `Dockerfile` (v1) and `Dockerfile-v2` = deprecated.
  - **Conventions / version pins**: document both pin sets — shared (base image
    `summerwind/actions-runner:ubuntu-24.04`, Composer `2.10.2`, Node `22`/`24`)
    and per-line (v3: PHP `8.4`, MongoDB `2.3.3`; v4: PHP `8.5`, MongoDB `2.5.5`).
  - **Build & verify commands**: give the build and smoke-check commands for
    both images (v3 expecting PHP 8.4, v4 expecting PHP 8.5).
  - **Release flow**: document the tag-suffix convention — `v*` → v3, `v*-php8.5`
    → v4 — and the image tags each produces.
  - **Guardrails**: keep "Do not edit `Dockerfile` or `Dockerfile-v2`" and the
    version-pin and `USER runner` rules; replace "v3 is the only Dockerfile CI
    builds" with the two-image, tag-selected model.
- `.kiro/steering/*` build guidance — rewrite end to end to cover both images:
  - **Scope**: v3 and v4 are both buildable active images; v1/v2 stay excluded.
  - **Per-line pins**: v3 (PHP 8.4, MongoDB 2.3.3) and v4 (PHP 8.5, MongoDB
    2.5.5), alongside the shared Composer/Node/base pins.
  - **Local build + smoke check**: commands for each image, with the v4 smoke
    check expecting PHP 8.5.
  - **CI build parity**: document the tag-suffix selection and the per-line
    image tags.
  - Preserve the layer-caching discipline, `gd` verification, checksum-verified
    Composer, and `USER runner` constraints for both images.

These are documentation edits; they do not change either shipped image.

## Data Models

Not applicable — this is Docker image and CI configuration, no application data
models.

## Error Handling

- **gd without FreeType/JPEG**: the `php -r "phpinfo();" | grep` checks in layer
  4 exit non-zero and fail the build (inherited from v3).
- **Composer checksum mismatch**: the SHA-384 comparison aborts the build
  before the installer runs (inherited from v3).
- **MongoDB extension incompatible with PHP 8.5**: mitigated by pinning the
  2.5.x line; if `pecl install mongodb-2.5.5` fails to compile against PHP 8.5
  headers, the build fails in layer 5, surfacing the problem in CI rather than
  at job runtime.
- **Wrong line built from a mistyped tag**: the line is derived purely from the
  tag suffix, so a typo (e.g. `v1.2.3-php85` instead of `-php8.5`) routes to the
  v3 fallback and publishes PHP 8.4 under that tag. Mitigation: the tag
  convention is documented, and only an exact `-php8.5` suffix selects v4; a
  mispush is corrected by pushing a correct tag (image tags are not force-moved
  by this workflow).

## Testing Strategy

1. **Local single-arch build** of `Dockerfile-v4`:
   ```bash
   docker build -f Dockerfile-v4 -t actions-runner-v4:local .
   ```
2. **Local smoke check** (Requirement 7.2):
   ```bash
   docker run --rm actions-runner-v4:local bash -lc '
     php -v
     php -m | grep -i mongodb
     composer --version
     node -v
   '
   ```
   Expected: PHP 8.5.x, `mongodb` present, Composer 2.10.2, Node v22.
3. **Multi-arch build** matching CI (heavier; needs Buildx):
   ```bash
   docker buildx build -f Dockerfile-v4 --platform linux/amd64,linux/arm64 -t actions-runner-v4:local .
   ```
4. **Regression check on v3**: confirm `Dockerfile-v3` still builds unchanged
   (its bytes are not modified by this work).
5. **Workflow validation**: the CI YAML is syntactically valid; the two
   build/push steps reference the correct Dockerfiles and non-colliding tags;
   and the `if:` conditions on `github.ref_name` select exactly one line per tag
   (a `v*-php8.5` tag runs only the v4 step, any other `v*` tag runs only the v3
   step). Full end-to-end publish is tag-driven and performed by the maintainer,
   not by this spec.

## Resolved decisions

These were previously open; each is now decided and is reflected throughout
this design.

1. **MongoDB extension pin**: pin `2.5.5` (the latest 2.5.x at authoring time).
   Used in Component 2 and the layer plan.
2. **v4 git-tag suffix / image-tag scheme**: use the `-php8.5` git-tag suffix
   with a `:php8.5-latest` moving tag on the same `jayscgi/actions-runner` repo.
   Used in Component 3's tag-convention table. A separate suffix or repo is not
   adopted.
3. **Node pins for v4**: identical to v3 — Node 22 default, Node 24 secondary.
   Reflected in layer 7 (unchanged from v3).
4. **Doc-edit breadth**: full rewrite of the steering build guidance to document
   v4 end to end (not a minimal note). Scope is detailed in Component 4.
