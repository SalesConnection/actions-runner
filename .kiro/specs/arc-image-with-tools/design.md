# Design: ARC Docker Image with Pre-built Tools

## 1. Architecture Overview

The image extends `summerwind/actions-runner:ubuntu-24.04` (Ubuntu 24.04 Noble) in a
single stage. There is no multi-stage build — all toolchains must be present at runtime
and the size savings from a multi-stage approach are negligible because compiled PHP
extensions still require their shared runtime libraries in the final image.

The layering strategy prioritises cache efficiency: the most stable layers (system
libraries, PHP) are placed early so that bumping only the MongoDB driver version or the
Node version doesn't invalidate those heavyweight layers.

```
summerwind/actions-runner:ubuntu-24.04   ← upstream ARC base (Ubuntu 24.04)
        │
        ▼
  ENV declarations                        ← no filesystem cost; sets DEBIAN_FRONTEND + NVM_DIR
        │
        ▼
  gnupg + software-properties-common      ← bootstrap tools for PPA registration
        │
        ▼
  ondrej/php PPA registration             ← apt-add-repository; separated so PPA key step
        │                                   is cached independently of system lib changes
        ▼
  System libraries (libcurl, libssl, …)   ← build-time + runtime deps; rarely change
        │
        ▼
  PHP 8.4-FPM + extensions + pecl         ← PHP runtime; changes on PHP version bump
        │
        ▼
  MongoDB 2.3.3 (pecl)                    ← isolated layer; version bump only re-runs this
        │
        ▼
  nvm + Node 22 (default) + Node 24       ← user-space install; isolated from system PHP
        │
        ▼
  USER runner                             ← restore ARC's required unprivileged user
```

---

## 2. Dockerfile Structure

### 2.1 Base Image

```dockerfile
FROM summerwind/actions-runner:ubuntu-24.04
```

Matches the ARC `summerwind` image track. All runner binaries and
configuration from the base image are preserved unchanged.

### 2.2 Environment Variables

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive \
    NVM_DIR=/home/runner/.nvm
```

`DEBIAN_FRONTEND=noninteractive` — set as `ENV` (not `ARG`) so it applies across every
subsequent layer, eliminating the need to repeat `-y` workarounds in each `apt-get` call.

`NVM_DIR` — declares the canonical install location once; referenced by both the nvm
install script and the shell rc-file injection step.

### 2.3 Bootstrap Layer (gnupg + software-properties-common)

Separated from the main system-library block. `gnupg` is needed to import the
`ondrej/php` PPA signing key; `software-properties-common` provides
`add-apt-repository`. These two packages almost never change, so isolating them
maximises cache hits when the system-library list is updated.

### 2.4 PHP PPA Registration

`add-apt-repository ppa:ondrej/php` is run as its own layer for the same reason:
the PPA URL is stable. Separating it means an update to the system-library list or
PHP version doesn't require re-fetching the PPA metadata.

### 2.5 System Libraries

All required libraries are installed in a single `RUN` command, followed immediately
by `rm -rf /var/lib/apt/lists/*` to keep the layer lean. They are placed before the PHP
layer because they are its build-time and runtime dependencies — if PHP is reinstalled,
these libraries are already cached. `build-essential` (gcc, make) is included because
`pecl` compiles the MongoDB extension from C source at build time.

> **Note:** `openssh-client` (Requirement 9) is **not installed** in `Dockerfile-v3`.
> SSH agent support is deferred — see Section 9.

### 2.6 PHP 8.4-FPM, Extensions, and pecl

Installs PHP from the ondrej/php PPA (Ubuntu 24.04 does not ship PHP 8.4 in its default
repos). `php8.4-dev` provides the headers needed by pecl. `php-pear` provides the pecl
binary. All extensions (`bcmath`, `curl`, `exif`, `gd`, `mbstring`, `xml`, `zip`,
`intl`, `gmp`, `redis`, `soap`, `sqlite3` (pdo + pdo_sqlite)) are enabled for both CLI
and FPM SAPIs via `phpenmod -v 8.4 bcmath curl exif gd intl mbstring gmp redis soap sqlite3 xml zip`.

`php8.4-sqlite3` provides the `sqlite3`, `pdo`, and `pdo_sqlite` extensions.
`php8.4-redis` provides Redis support.

A build-time verification step checks that the `gd` extension reports FreeType and JPEG
support (the ondrej/php `php8.4-gd` package builds with both by default; the check fails
the build early if it doesn't).

### 2.7 MongoDB 2.3.3 (pecl)

Isolated in its own `RUN` layer so bumping the driver version doesn't re-run the PHP
installation. After `pecl install mongodb-2.3.3`, a drop-in `.ini` is written to
`/etc/php/8.4/mods-available/mongodb.ini` and `phpenmod -v 8.4 mongodb` symlinks it
into both `cli/conf.d` and `fpm/conf.d`.

### 2.8 nvm, Node 22, and Node 24

nvm is installed as root with `HOME=/home/runner` so the install lands in
`/home/runner/.nvm`. Ownership is then corrected to `runner:runner`.

Both Node versions are installed sequentially. Node 22 is set as the default alias so
`node` and `npm` resolve to v22 in any shell without an explicit `nvm use`. Node 24
remains available for workflows that need it.

Shell init lines are appended to both `.bashrc` (interactive non-login) and `.profile`
(login shells). The nvm-managed `bin` directory for the default version is also added to
`/etc/environment` PATH so that non-interactive, non-login shells (the default in GitHub
Actions steps) can resolve `node` and `npm` without sourcing nvm manually.

### 2.9 USER Instruction

`USER runner` is the final instruction. All preceding steps that require root have
completed. This satisfies the ARC requirement that the runner user is the active user
when the container starts.

---

## 3. Layer Ordering Rationale

| # | Layer | Cache stability | Rationale |
|---|-------|----------------|-----------|
| 1 | ENV | Immutable until changed | Zero filesystem cost; must precede all RUN layers that reference the vars |
| 2 | gnupg + s-p-c | Very stable | Prerequisite for PPA; rarely changes |
| 3 | ondrej/php PPA | Stable | URL doesn't change; isolated so lib changes don't re-fetch PPA metadata |
| 4 | System libraries | Stable, ~120 MB | Large layer; placed early so PHP version bumps don't re-download it |
| 5 | PHP 8.4 + extensions | Changes on PHP bumps | Depends on layers 2–4 being cached |
| 6 | MongoDB pecl | Changes on driver bumps | Isolated; doesn't invalidate PHP layer |
| 7 | nvm + Node 22 + 24 | Changes on Node bumps | User-space; isolated from system PHP |
| 8 | USER runner | Immutable | Must be last |

---

## 4. PHP Extension Configuration

### gd with FreeType and JPEG

`php8.4-gd` from the ondrej/php PPA is compiled with `--with-freetype` and
`--with-jpeg`. A verification step in the Dockerfile confirms this at build time:

```bash
php -r "phpinfo();" | grep -i "freetype" > /dev/null
php -r "phpinfo();" | grep -i "jpeg" > /dev/null
```

If either string is absent the build fails immediately rather than shipping a silently
incomplete extension.

### mongodb.so registration

```bash
echo "extension=mongodb.so" | sudo tee /etc/php/8.4/mods-available/mongodb.ini
sudo phpenmod -v 8.4 mongodb
```

`phpenmod` creates symlinks in `/etc/php/8.4/cli/conf.d/` and
`/etc/php/8.4/fpm/conf.d/`, enabling the extension for both SAPIs.

---

## 5. nvm and Node Availability Strategy

### The Challenge

GitHub Actions runner steps execute as non-interactive, non-login bash shells. The
standard nvm shell init (appended to `.bashrc`) is skipped in this context, so `node`
and `npm` are not on `PATH` unless the step explicitly sources nvm or the default Node
bin directory is on the system PATH.

### Approach: rc-file injection + /etc/environment PATH entry

Two complementary mechanisms ensure `node` and `npm` are always available:

1. **rc-file injection** — nvm init lines in `.bashrc` and `.profile` cover interactive
   and login shells, and any workflow step that uses `bash --login` or `source ~/.nvm/nvm.sh`.

2. **`/etc/environment` PATH entry** — the nvm-managed bin directory for the default
   version (`/home/runner/.nvm/versions/node/v22.x.x/bin`) is appended to the system
   PATH via `/etc/environment`. This makes `node` and `npm` available in non-interactive
   shells without any sourcing required.

The `/etc/environment` entry is written during the build after `nvm install 22` completes,
using the resolved path:

```bash
NODE22_BIN=$(. $NVM_DIR/nvm.sh && nvm which 22 | xargs dirname) && \
echo "PATH=$NODE22_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  | sudo tee -a /etc/environment
```

Workflows that need Node 24 use `source ~/.nvm/nvm.sh && nvm use 24` or
`bash --login -c "nvm use 24 && ..."`.

---

## 6. Multi-Arch Considerations

| Component | amd64 | arm64 | Notes |
|-----------|:-----:|:-----:|-------|
| Base image | ✓ | ✓ | `summerwind/actions-runner:ubuntu-24.04` publishes both platforms |
| ondrej/php PPA | ✓ | ✓ | Provides arm64 debs for Ubuntu Noble |
| System libraries | ✓ | ✓ | Available in Ubuntu main for both arches |
| nvm | ✓ | ✓ | Shell script; architecture-agnostic |
| Node 22 & 24 | ✓ | ✓ | nvm downloads the correct binary per arch |
| mongodb-2.3.3 (pecl) | ✓ | ✓ | Compiles from source; no pre-built binary required |

No platform-specific `RUN --platform` branching is needed. The existing workflow uses
`docker/setup-qemu-action@v2` to emulate arm64 on amd64 build hosts. Note that
`pecl install` under QEMU emulation on arm64 is slow (~15–30 min) due to C compilation;
this is a build-time concern only.

---

## 7. Key Design Decisions

### Decision 1: apt-installed PHP vs docker-official PHP image

**Chosen:** `apt install php8.4-*` from the ondrej/php PPA.
**Alternative:** Re-base on `php:8.4-fpm` official image, or copy PHP out of it via
multi-stage.
**Rationale:** Requirement 1.1 mandates the ARC base image. Re-basing on the official
PHP image loses all runner binaries. Copying PHP out of it is fragile because shared
library paths differ. The ondrej/php PPA is the standard community source for
out-of-default PHP versions on Ubuntu and is production-proven in CI environments.

### Decision 2: nvm installed as root into runner's home

**Chosen:** Run the nvm install script as root with `HOME=/home/runner`, then
`chown -R runner:runner /home/runner/.nvm`.
**Alternative:** `USER runner` mid-Dockerfile, install nvm, then switch back to root.
**Rationale:** Switching users mid-file is confusing and requires a second `USER root`
instruction before any remaining root steps. The install-as-root-then-chown pattern
keeps `USER runner` as the single, final instruction and results in identical ownership.

### Decision 3: Pre-install Node 22 (default) and Node 24

**Chosen:** `nvm install 22 && nvm install 24 && nvm alias default 22`.
**Alternative (previous):** No pre-installed Node version.
**Rationale:** Per user decision, Node 22 (current LTS) and Node 24 (next LTS) are both
pre-installed to cover the two most common CI targets. Defaulting to 22 preserves
backwards compatibility for existing workflows while making 24 available without any
install step for teams adopting it.

### Decision 4: MongoDB driver pinned to 2.3.3

**Chosen:** `pecl install mongodb-2.3.3` (explicit version).
**Alternative:** `pecl install mongodb` (latest).
**Rationale:** Explicit pinning prevents unexpected API or behaviour changes on a PECL
release. The version is visible in git history; a future bump is a one-line change.

### Decision 5: Single-stage build

**Chosen:** Single `FROM` stage.
**Alternative:** Multi-stage — compile PHP extensions in a builder stage, copy `.so`
files to a clean final stage.
**Rationale:** PHP extensions require their shared runtime libraries at runtime (e.g.
`libmongoc`, `libfreetype`). A clean final stage would still need to install those same
libraries, yielding no meaningful size reduction while adding significant Dockerfile
complexity.

---

## 8. Complete Dockerfile-v3

The listing below is an exact copy of `Dockerfile-v3` as it exists in the repository.

```dockerfile
# Dockerfile-v3
# ARC runner image with nvm, Node.js 22 (default) + 24, PHP 8.4-FPM,
# MongoDB PHP extension 2.3.3, and required system libraries.
#
# Base:    summerwind/actions-runner:ubuntu-24.04
# Targets: linux/amd64, linux/arm64

FROM summerwind/actions-runner:ubuntu-24.04

# ── Environment ────────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    NVM_DIR=/home/runner/.nvm

# ── Bootstrap: gnupg + software-properties-common ─────────────────────────────
# Required to import the ondrej/php PPA signing key and run add-apt-repository.
# Isolated layer so changes to the system-library list below don't invalidate this.
RUN sudo apt-get update -yq && \
    sudo apt-get install -yq --no-install-recommends \
        gnupg \
        software-properties-common && \
    sudo rm -rf /var/lib/apt/lists/*

# ── PHP 8.4 PPA ────────────────────────────────────────────────────────────────
# Ubuntu 24.04 does not ship PHP 8.4 in its default repositories.
# The ondrej/php PPA is the standard community source for PHP 8.4 on Ubuntu.
RUN sudo add-apt-repository -y ppa:ondrej/php && \
    sudo apt-get update -yq

# ── System libraries ───────────────────────────────────────────────────────────
# Build-time and runtime dependencies for PHP extensions (gd, curl, zip, intl,
# gmp, mongodb). Installed before PHP so this layer is cached on PHP version bumps.
RUN sudo apt-get install -yq --no-install-recommends \
        build-essential \
        libcurl4-openssl-dev \
        pkg-config \
        libssl-dev \
        libfreetype6-dev \
        libjpeg-turbo8-dev \
        libpng-dev \
        zlib1g-dev \
        libzip-dev \
        libonig-dev \
        libxml2-dev \
        libicu-dev \
        libgmp-dev && \
    sudo rm -rf /var/lib/apt/lists/*

# ── PHP 8.4-FPM + extensions ───────────────────────────────────────────────────
# php8.4-dev     — PHP headers required by pecl to compile the MongoDB extension.
# php-pear       — provides the pecl command.
# php8.4-gd      — built by ondrej/php with --with-freetype and --with-jpeg.
# php8.4-sqlite3 — provides sqlite3, pdo, and pdo_sqlite extensions.
# Verification step fails the build if gd lacks FreeType or JPEG support.
RUN sudo apt-get update -yq && \
    sudo apt-get install -yq --no-install-recommends \
        php8.4 \
        php8.4-fpm \
        php8.4-cli \
        php8.4-dev \
        php8.4-bcmath \
        php8.4-curl \
        php8.4-exif \
        php8.4-gd \
        php8.4-mbstring \
        php8.4-xml \
        php8.4-zip \
        php8.4-intl \
        php8.4-gmp \
        php8.4-soap \
        php8.4-sqlite3 \
        php8.4-redis \
        php-pear && \
    php -r "phpinfo();" | grep -i "freetype" > /dev/null && \
    php -r "phpinfo();" | grep -i "jpeg" > /dev/null && \
    sudo phpenmod -v 8.4 bcmath curl exif gd intl mbstring gmp redis soap sqlite3 xml zip && \
    sudo rm -rf /var/lib/apt/lists/*

# ── MongoDB PHP extension 2.3.3 (via pecl) ─────────────────────────────────────
# Compiles the driver against PHP 8.4 headers installed above.
# Isolated layer: bumping the driver version only re-runs this step.
RUN sudo pecl install mongodb-2.3.3 && \
    echo "extension=mongodb.so" | sudo tee /etc/php/8.4/mods-available/mongodb.ini > /dev/null && \
    sudo phpenmod -v 8.4 mongodb

# ── nvm + Node.js 22 (default) + Node.js 24 ───────────────────────────────────
# Installed as root with HOME overridden so nvm lands in /home/runner/.nvm.
# Ownership is corrected to runner:runner after installation.
#
# Both Node 22 and Node 24 are pre-installed; 22 is set as the default alias.
#
# /etc/environment PATH is updated with the Node 22 bin directory so that
# non-interactive, non-login shells (the GitHub Actions default) can resolve
# `node` and `npm` without sourcing nvm explicitly.
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | sudo HOME=/home/runner bash && \
    sudo chown -R runner:runner /home/runner/.nvm && \
    # Install Node 22 and 24; set 22 as default
    bash -c ". $NVM_DIR/nvm.sh && nvm install 22 && nvm install 24 && nvm alias default 22 && nvm use default" && \
    # Append nvm init to .bashrc (interactive non-login shells)
    echo 'export NVM_DIR="$HOME/.nvm"'                                      >> /home/runner/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'                >> /home/runner/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> /home/runner/.bashrc && \
    # Append nvm init to .profile (login shells)
    echo 'export NVM_DIR="$HOME/.nvm"'                                      >> /home/runner/.profile && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'                >> /home/runner/.profile && \
    # Add Node 22 bin to system PATH for non-interactive shells
    NODE22_BIN=$(bash -c ". $NVM_DIR/nvm.sh && nvm which 22 | xargs dirname") && \
    echo "PATH=${NODE22_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        | sudo tee /etc/environment > /dev/null

# ── Restore runner user ────────────────────────────────────────────────────────
# ARC requires the container to run as the `runner` user.
USER runner
```

### Validation (Task 11)

A static validation task (task 11) was added to the spec to verify `Dockerfile-v3`
correctness against the spec checklist. The checks include: confirming the `FROM`
instruction, `ENV` declarations, bootstrap layer, PPA registration step, all 13 system
libraries, PHP packages and `phpenmod` calls, FreeType/JPEG verification greps, MongoDB
pecl install and `.ini` write, nvm setup with both Node versions, and `USER runner` as
the final instruction. A `docker build --check` dry-run is also run when Docker is
available to catch syntax errors without a full build.

---

## 9. SSH Agent (Requirement 9 — Deferred)

> **Not implemented in `Dockerfile-v3`.** Requirement 9 (SSH Agent) is out of scope for
> this version of the image. `openssh-client` is **not** installed, and `ssh-agent` /
> `ssh-add` are **not** present in the image.
>
> When SSH agent support is added in a future iteration, the recommended approach is to
> consolidate `openssh-client` into the existing system libraries `RUN` block (Section
> 2.5) to satisfy Requirement 9.2 (no additional layer). The binaries are owned by root
> with world-execute permissions, so the runner user can invoke them without `sudo`
> once the package is installed.
>
> No agent socket or daemon should be pre-started in the image. Jobs would start the
> agent on demand:
>
> ```bash
> eval $(ssh-agent -s)
> echo "${{ secrets.DEPLOY_KEY }}" | ssh-add -
> ```

---

## 10. Workflow Integration Notes

The `.github/workflows/docker-build.yml` workflow has been updated to build
`Dockerfile-v3`. The relevant step currently reads:

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    file: Dockerfile-v3
    platforms: linux/amd64,linux/arm64
    push: true
    tags: jayscgi/actions-runner:${{ github.ref_name }},jayscgi/actions-runner:latest
    labels: jayscgi/actions-runner:${{ github.ref_name }}
```

All other workflow steps (QEMU, Buildx, Docker Hub login) are already compatible with
this image and required no changes.
