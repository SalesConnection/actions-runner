# Requirements: ARC Docker Image with Pre-built Tools

## Introduction

This specification covers the construction of a custom ARC (Actions Runner Controller) Docker image that extends the official GitHub Actions runner base image with a set of pre-installed development tools and PHP infrastructure. The resulting image is intended for use as a self-hosted runner in GitHub Actions workflows that require Node.js (via nvm), PHP 8.4 with FPM, MongoDB integration via PHP, and a set of common system libraries — all ready to use without additional provisioning steps at job runtime.

The image is built and distributed via Docker Hub under the `jayscgi/actions-runner` repository, tagged by version and `latest`, targeting both `linux/amd64` and `linux/arm64` platforms. The Dockerfile shall be named `Dockerfile-v3` to follow the existing versioning convention.

---

## Requirements

### Requirement 1: Base Image Selection

**User Story:** As a platform engineer, I want the custom runner image to be based on the official ARC runner image so that it remains compatible with Actions Runner Controller and receives upstream security updates.

1. The image shall use `ghcr.io/actions/actions-runner:2.336.0` as the base image.
2. The image shall preserve all components of the base image (including optional components such as example workflows and documentation) to ensure nothing breaks; where the addition of new tools or dependencies requires modifying non-essential base image files, such modifications are permitted, but runner-critical files and configurations shall not be removed or overwritten.
3. The runner user (`runner`) shall remain the default active user at the end of the Dockerfile.

### Requirement 2: System Libraries

**User Story:** As a developer using the runner, I want all required system-level development libraries pre-installed so that PHP extensions and other tools compile and link correctly without manual intervention.

1. The image shall install the following system libraries via `apt-get`: `gnupg`, `libcurl4-openssl-dev`, `pkg-config`, `libssl-dev`, `libfreetype6-dev`, `libjpeg62-turbo-dev`, `libpng-dev`, `zlib1g-dev`, `libzip-dev`, `libonig-dev`, `libxml2-dev`, `libicu-dev`, `libgmp-dev`.
2. The image shall run `apt-get update` before installing any packages.
3. The image shall use non-interactive flags (e.g., `DEBIAN_FRONTEND=noninteractive`, `-yq`) during all package installation steps.
4. The image shall remove `/var/lib/apt/lists/*` after each `RUN` layer that performs `apt-get` operations to keep layer sizes minimal.

### Requirement 3: PHP-FPM 8.4 Installation

**User Story:** As a developer using the runner, I want PHP 8.4 with FPM and a comprehensive set of extensions pre-installed so that PHP-based CI jobs can run immediately without any setup steps.

1. The image shall install PHP 8.4 and `php8.4-fpm` from a compatible package source (e.g., the `ondrej/php` PPA) that provides PHP 8.4 packages for Ubuntu 24.04.
2. The image shall install and enable the following PHP extensions: `curl`, `gd`, `mbstring`, `xml`, `zip`, `intl`, `gmp`.
3. The `gd` extension shall be compiled with FreeType and JPEG support (e.g., `--with-freetype --with-jpeg` or equivalent flags).
4. All installed PHP extensions shall be enabled for both the PHP CLI and PHP-FPM SAPIs.
5. The `php-fpm` binary and configuration shall be present and in a valid, startable state after the image build.
6. `pecl` (from `php-pear` or the PHP package source) shall be installed and available for use by subsequent extension installation steps.

### Requirement 4: MongoDB PHP Extension

**User Story:** As a developer using the runner, I want the MongoDB PHP extension pre-installed so that PHP jobs interacting with MongoDB can run without additional extension compilation at job runtime.

1. The image shall install the MongoDB PHP extension version `2.3.3` using `pecl install mongodb-2.3.3`.
2. The MongoDB extension shall be enabled for both the PHP CLI and PHP-FPM SAPIs.
3. The `pecl` installation step shall occur after all required system libraries (Requirement 2) and PHP development headers are available in the image layer.

### Requirement 5: Node Version Manager (nvm) and Node.js 22

**User Story:** As a developer using the runner, I want nvm pre-installed with Node.js 22 as the default version so that CI jobs can use Node immediately without any setup steps, while still being able to switch versions when needed.

1. The image shall install the latest stable release of nvm from `https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh` or the equivalent canonical installation script.
2. nvm shall be installed into the runner user's home directory (e.g., `/home/runner/.nvm`).
3. The nvm shell initialization (sourcing `$NVM_DIR/nvm.sh`) shall be appended to `/home/runner/.bashrc` and `/home/runner/.profile` so that `nvm`, `node`, and `npm` are available in both interactive and non-interactive shell sessions used by the runner.
4. The runner user shall be able to invoke `nvm`, `node`, and `npm` without requiring `sudo` or additional shell configuration.
5. The image shall pre-install Node.js 22 and Node.js 24 via `nvm install 22` and `nvm install 24`.
6. Node.js 22 shall be set as the nvm default alias (`nvm alias default 22`) so that `node` and `npm` resolve to v22 in any shell session without an explicit `nvm use` call.
7. The `node` and `npm` binaries for the default version (22) shall be accessible on `PATH` in non-interactive shells used by GitHub Actions job steps.
8. CI jobs requiring Node.js 24 shall be able to activate it with `nvm use 24` without any additional installation steps.

### Requirement 6: Runner User Permissions

**User Story:** As a platform engineer, I want the runner user to have access to all installed tools without needing `sudo` for normal operations so that jobs run securely with least privilege.

1. The runner user shall be able to invoke `php`, `php8.4-fpm`, and `pecl`-enabled extensions without requiring `sudo` for normal operations (e.g., running scripts, executing PHP), regardless of whether additional group memberships have been configured.
2. Where the runner user requires membership in additional operating system groups to access installed tools or sockets (e.g., a `php` or `www-data` group), those group memberships shall be configured during the image build; however, PHP tool access shall not be gated solely on group membership.
3. The image shall not grant the runner user unrestricted `sudo` access beyond what the base image already provides; if the base image grants no `sudo` access, the custom image shall not introduce unrestricted `sudo` access either.

### Requirement 7: Image Optimization

**User Story:** As a platform engineer, I want the Docker image to be as small and cache-efficient as possible so that image pulls are fast and CI build times are minimized.

1. The Dockerfile shall consolidate related installation steps into as few `RUN` layers as is practical to minimize total image layer count and overall image size.
2. Temporary build artifacts, downloaded installer scripts, and cached package data shall be removed within the same `RUN` layer in which they are created.
3. The image shall be buildable on both `linux/amd64` and `linux/arm64` platforms without platform-specific branching in the Dockerfile, unless a dependency is unavailable on a given platform, in which case a comment shall document the exception.

### Requirement 8: Maintainability

**User Story:** As a future maintainer, I want the Dockerfile to be clearly commented and to have all pinned versions explicitly stated so that dependency updates are straightforward to identify and apply.

1. The Dockerfile shall include inline comments identifying the purpose of each major installation block (e.g., system libraries, PHP, nvm, MongoDB extension).
2. All pinned dependency versions (e.g., `mongodb-2.3.3`, `ghcr.io/actions/actions-runner:2.336.0`) shall be explicitly stated in the relevant `RUN` commands or `FROM` instruction.
3. The Dockerfile shall be named `Dockerfile-v3` to follow the existing versioning convention (`Dockerfile`, `Dockerfile-v2`) in the repository.

---

## Constraints and Assumptions

- **Base image OS**: `ghcr.io/actions/actions-runner:2.336.0` is Ubuntu 24.04 (Noble Numbat)-based. All package sources and installation commands target Ubuntu 24.04.
- **PHP 8.4 availability**: PHP 8.4 may not be present in the default Ubuntu 24.04 `apt` repository. An external PPA (e.g., `ppa:ondrej/php`) shall be used; the specification does not mandate a specific mechanism as long as Requirements 3.1–3.6 are satisfied.
- **No daemon management**: The image runs in an ephemeral runner container. Services such as `php-fpm` are not started as system daemons; CI jobs start them as needed. The requirement is that binaries and configuration are present and valid.
- **Network access**: The build environment has outbound internet access to reach `apt` repositories, GitHub (for nvm), and PECL (for the MongoDB extension).
- **CI/CD pipeline**: The existing workflow at `.github/workflows/docker-build.yml` builds and pushes on version tags. This specification does not modify the workflow; only the Dockerfile is in scope.
- **Secrets**: Docker Hub credentials (`DOCKER_USERNAME`, `DOCKER_PASSWORD`) are stored as GitHub Actions secrets and are out of scope.
