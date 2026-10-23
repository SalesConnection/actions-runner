# Requirements: PHP 8.5 Support via a New `Dockerfile-v4`

## Introduction

This specification covers adding **PHP 8.5** support to the custom ARC (Actions
Runner Controller) self-hosted runner image. Rather than modifying or
deprecating the existing `Dockerfile-v3` (which ships PHP 8.4), this work
introduces a **new, parallel `Dockerfile-v4`** that mirrors v3's structure but
targets PHP 8.5 and the dependency versions required to support it.

Both images are kept alive side by side: `Dockerfile-v3` continues to produce
the PHP 8.4 runner, and `Dockerfile-v4` produces the PHP 8.5 runner. The CI
build workflow (`.github/workflows/docker-build.yml`) stays tag-driven and
selects the line **from the git tag pattern**: a plain `v*` tag builds and
publishes v3 (PHP 8.4), and a `v*-php8.5` tag builds and publishes v4 (PHP 8.5),
under distinct Docker Hub tags. Each tag push publishes exactly one line, and
consumers can pin to either PHP line.

The work preserves every hard constraint of the existing image: the
`ondrej/php` PPA for PHP packages, checksum-verified Composer, deliberate
per-concern layer ordering, the `/etc/environment` PATH entry for Node, and the
final `USER runner` instruction required by ARC.

---

## Dependency support findings (verified)

These findings informed the version pins below and are recorded here so the
pins are traceable:

- **PHP 8.5** is Generally Available and is published in the `ondrej/php` PPA
  for Ubuntu 24.04 (noble) under the `php8.5-*` package names, matching the v3
  package pattern. No base-image change is required.
- **MongoDB PHP extension**: PHP 8.5 compatibility was added in the MongoDB PHP
  **extension 2.x line**; the currently pinned v3 driver `2.3.3` predates PHP
  8.5 support. The latest 2.5.x release at the time of writing is **`2.5.5`**
  (a security release addressing CVE-2026-112368). `Dockerfile-v4` therefore
  pins the MongoDB extension to **`2.5.5`**, compiled against PHP 8.5 headers.
- **Composer `2.10.2`** is PHP-runtime-independent and carries over unchanged.
- **Node.js 22 / 24 via nvm** are independent of the PHP line and carry over
  unchanged.
- **System libraries** (gd/FreeType/JPEG, curl, zip, intl, gmp, mongodb build
  deps, `openssh-client`) are unchanged; they are OS-level, not PHP-version
  specific.

> The exact MongoDB extension patch (`2.5.5`) and the decision to keep Composer
> and Node pins identical to v3 are design decisions subject to confirmation
> during the design phase; see `design.md`.

---

## Requirements

### Requirement 1: New `Dockerfile-v4` (do not deprecate v3)

**User Story:** As a platform engineer, I want a new `Dockerfile-v4` for the
PHP 8.5 image so that the existing PHP 8.4 `Dockerfile-v3` continues to build
and ship unchanged.

1. A new Dockerfile named `Dockerfile-v4` SHALL be created at the repository
   root.
2. `Dockerfile-v3` SHALL remain unmodified and SHALL continue to build the PHP
   8.4 image; it SHALL NOT be deprecated, renamed, or removed by this work.
3. `Dockerfile` (v1) and `Dockerfile-v2` SHALL remain untouched; they stay
   deprecated as before.
4. `Dockerfile-v4` SHALL use `summerwind/actions-runner:ubuntu-24.04` as its
   base image, identical to v3.
5. `Dockerfile-v4` SHALL end with the `USER runner` instruction as its final
   instruction, as ARC requires.

### Requirement 2: PHP 8.5 Installation

**User Story:** As a developer using the v4 runner, I want PHP 8.5 with FPM and
the same extension set as v3 so that PHP 8.5 CI jobs run immediately without
setup.

1. `Dockerfile-v4` SHALL install PHP 8.5 and `php8.5-fpm` from the `ondrej/php`
   PPA (the same PPA used by v3), which provides PHP 8.5 packages for Ubuntu
   24.04.
2. `Dockerfile-v4` SHALL install and enable the same set of PHP extensions as
   v3, using the `php8.5-*` package names: `bcmath`, `curl`, `exif`, `gd`,
   `intl`, `mbstring`, `gmp`, `redis`, `soap`, `sqlite3` (providing `pdo` and
   `pdo_sqlite`), `xml`, `zip`.
3. The `gd` extension SHALL have FreeType and JPEG support, and the build SHALL
   fail if either is missing (preserving v3's build-time `gd` verification).
4. All installed PHP extensions SHALL be enabled for both the PHP CLI and
   PHP-FPM SAPIs (via `phpenmod -v 8.5 ...`).
5. `php8.5-dev` SHALL be installed so that `pecl` can compile the MongoDB
   extension against PHP 8.5 headers.
6. `php-pear` (providing `pecl`) SHALL be installed.
7. Every PHP version reference in `Dockerfile-v4` SHALL be `8.5` (package
   names, `phpenmod -v 8.5`, and the `/etc/php/8.5/...` extension-config path).

### Requirement 3: MongoDB PHP Extension Compatible with PHP 8.5

**User Story:** As a developer using the v4 runner, I want a MongoDB PHP
extension that supports PHP 8.5 so that MongoDB jobs run without runtime
compilation.

1. `Dockerfile-v4` SHALL install the MongoDB PHP extension version **`2.5.5`**
   via `pecl install mongodb-2.5.5`.
2. The MongoDB extension SHALL be compiled after PHP 8.5 and `php8.5-dev` are
   installed so it links against PHP 8.5 headers.
3. The extension config SHALL be written to the PHP 8.5 path
   (`/etc/php/8.5/mods-available/mongodb.ini`) and enabled with
   `phpenmod -v 8.5 mongodb` for both CLI and FPM SAPIs.
4. The pinned MongoDB extension version SHALL be a release that officially
   supports PHP 8.5 (the 2.5.x line); it SHALL NOT be pinned to `2.3.3` (the v3
   pin), which predates PHP 8.5 support.

### Requirement 4: Carry-over Components Unchanged from v3

**User Story:** As a maintainer, I want the non-PHP-specific parts of v4 to be
identical to v3 so that the two images differ only in their PHP line and its
directly dependent components.

1. `Dockerfile-v4` SHALL install the same system libraries as v3 (including
   `openssh-client`) in a dedicated layer before PHP.
2. `Dockerfile-v4` SHALL install Composer version `2.10.2` using the official
   installer, SHALL verify the installer's SHA-384 checksum against
   `https://composer.github.io/installer.sig` before executing it, and SHALL
   abort the build on a checksum mismatch. The downloaded installer script
   SHALL be removed within the same `RUN` layer.
3. `Dockerfile-v4` SHALL install nvm with Node.js 22 (default) and Node.js 24,
   and SHALL preserve the `/etc/environment` PATH entry for the Node 22 bin
   directory so non-interactive, non-login shells resolve `node`/`npm` without
   sourcing nvm.
4. The nvm initialization SHALL be appended to `/home/runner/.bashrc` and
   `/home/runner/.profile`, and `/home/runner/.nvm` ownership SHALL be
   corrected to `runner:runner`, identical to v3.

### Requirement 5: Deliberate Layer Ordering Preserved

**User Story:** As a maintainer, I want v4 to keep v3's per-concern layer
isolation so that a bump in one area does not invalidate the cache for
unrelated areas.

1. `Dockerfile-v4` SHALL keep each concern in its own `RUN` layer in the same
   order as v3: (1) bootstrap (`gnupg`, `software-properties-common`),
   (2) `ondrej/php` PPA, (3) system libraries, (4) PHP + extensions,
   (5) MongoDB driver via `pecl`, (6) Composer, (7) nvm + Node.
2. Unrelated steps SHALL NOT be merged into a single layer.
3. Each `apt-get` layer SHALL run `apt-get update` first, use non-interactive
   flags, and remove `/var/lib/apt/lists/*` at the end of the layer.

### Requirement 6: CI Selects the PHP Line from the Git Tag Pattern

**User Story:** As a platform engineer, I want the release build to pick which
PHP version (v3 / PHP 8.4 or v4 / PHP 8.5) to build and publish from the git
tag I push, so that I select a line without a manual input and never publish
both lines at once.

1. The release build SHALL publish exactly one image line (v3 or v4) per tag
   push, determined by the tag name; it SHALL NOT publish both lines on a single
   tag push.
2. The workflow SHALL remain tag-driven on `push` of a `v*` tag, with no
   `workflow_dispatch` input and no manual line selector.
3. WHEN the pushed tag matches the v4 suffix pattern (a `v*` tag ending in
   `-php8.5`, e.g. `v1.2.3-php8.5`), THE workflow SHALL build and publish the v4
   (PHP 8.5) line from `Dockerfile-v4`.
4. WHEN the pushed tag is a `v*` tag that does NOT end in `-php8.5` (e.g.
   `v1.2.3`), THE workflow SHALL build and publish the v3 (PHP 8.4) line from
   `Dockerfile-v3`, preserving existing release behavior.
5. A single workflow file (`.github/workflows/docker-build.yml`) SHALL implement
   both lines rather than a second workflow file; the line is chosen inside the
   job by a step-level condition on the tag name (`github.ref_name`). (Rationale:
   GitHub's `on.push.tags` glob cannot branch to different jobs by sub-pattern,
   and one workflow keeps the shared QEMU/Buildx/Docker Hub login setup in a
   single place.)
6. WHEN the v3 line is built, THE workflow SHALL publish to the existing tags so
   that existing consumers are not broken:
   `jayscgi/actions-runner:<tag>` and `jayscgi/actions-runner:latest`.
7. WHEN the v4 line is built, THE workflow SHALL publish to **distinct,
   non-colliding** tags that clearly denote the PHP 8.5 line (the image tag
   derived from the git tag, e.g. `jayscgi/actions-runner:v1.2.3-php8.5`, plus a
   `php8.5`-scoped moving tag). The exact tagging scheme is a design decision
   (see `design.md`); the chosen scheme SHALL NOT overwrite the v3 `<tag>` or
   `latest` tags.
8. Every image the workflow builds SHALL be built multi-arch for `linux/amd64`
   and `linux/arm64`, matching current behavior.
9. The workflow SHALL continue to authenticate to Docker Hub using the existing
   `DOCKER_USERNAME` / `DOCKER_PASSWORD` repository secrets; no new secrets SHALL
   be introduced.
10. The workflow SHALL continue to run on the `self-hosted` runner.
11. This spec SHALL NOT push tags or publish images itself; publishing happens
    only through the workflow when a maintainer pushes a matching tag.

### Requirement 7: Build-time Verification

**User Story:** As a maintainer, I want v4 to self-verify its toolchain at build
time so that a broken PHP 8.5 build fails fast in CI.

1. The PHP layer in `Dockerfile-v4` SHALL fail the build if `gd` lacks FreeType
   or JPEG support (same check as v3).
2. After a successful local build, the toolchain SHALL be verifiable with a
   smoke check confirming PHP 8.5 is active, the `mongodb` extension is loaded,
   Composer reports `2.10.2`, and Node 22 is active:

   ```bash
   docker run --rm actions-runner-v4:local bash -lc '
     php -v
     php -m | grep -i mongodb
     composer --version
     node -v
   '
   ```

### Requirement 8: Maintainability and Version Pinning

**User Story:** As a future maintainer, I want `Dockerfile-v4` clearly commented
with every pinned version explicit so that future updates are easy to locate.

1. `Dockerfile-v4` SHALL include inline comments identifying each major
   installation block, matching v3's documentation style.
2. All pinned versions SHALL be explicit in the relevant instructions:
   PHP `8.5`, MongoDB extension `2.5.5`, Composer `2.10.2`, Node `22`/`24`,
   base image `summerwind/actions-runner:ubuntu-24.04`.
3. The header comment of `Dockerfile-v4` SHALL state that it is the PHP 8.5
   variant and that `Dockerfile-v3` remains the PHP 8.4 variant.
4. Project documentation and agent-guidance files that currently describe v3 as
   "the active image" (notably `AGENTS.md` and `.kiro/steering/`) SHALL be
   updated to reflect that v3 (PHP 8.4) and v4 (PHP 8.5) are both active,
   without marking v3 deprecated. (Scope of doc edits is refined in
   `design.md`.)

---

## Constraints and Assumptions

- **Base image OS**: `summerwind/actions-runner:ubuntu-24.04` (Ubuntu 24.04,
  noble). PHP 8.5 is sourced from `ppa:ondrej/php`, the same PPA v3 uses for PHP
  8.4.
- **No daemon management**: As with v3, `php-fpm` is not started as a system
  daemon; the requirement is that binaries and config are present and valid.
- **Network access**: The build reaches `apt`, the `ondrej/php` PPA, GitHub
  (nvm), PECL (MongoDB extension), and `getcomposer.org` / `composer.github.io`.
- **No unverified remote scripts as root**: Any new network download SHALL be
  checksum-verified, matching the Composer pattern. (No new downloads beyond the
  v3 set are expected.)
- **Secrets**: `DOCKER_USERNAME` / `DOCKER_PASSWORD` remain GitHub repo secrets
  and are out of scope.
- **MongoDB extension patch**: `2.5.5` is the latest 2.5.x at authoring time;
  the design phase confirms whether to pin `2.5.5` exactly or track a different
  2.5.x patch.
