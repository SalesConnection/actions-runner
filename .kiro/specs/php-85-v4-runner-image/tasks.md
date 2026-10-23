# Implementation Plan: PHP 8.5 Support via a New `Dockerfile-v4`

- [x] 1. Create `Dockerfile-v4` as a PHP 8.5 variant of `Dockerfile-v3`
  - Copy `Dockerfile-v3` to a new `Dockerfile-v4` at the repo root, keeping all
    seven layers in the same order.
  - Update the header comment to state v4 is the PHP 8.5 variant and that v3
    remains the PHP 8.4 variant.
  - Leave layers 0–3 (FROM/ENV, bootstrap, `ondrej/php` PPA, system libraries),
    layer 6 (Composer `2.10.2`, checksum-verified), layer 7 (nvm + Node 22/24 +
    `/etc/environment` PATH), and the final `USER runner` byte-for-byte
    identical to v3.
  - _Requirements: 1.1, 1.4, 1.5, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 8.1, 8.3_

- [x] 2. Convert the PHP layer to PHP 8.5
  - In `Dockerfile-v4` layer 4, replace every `php8.4-*` package with its
    `php8.5-*` equivalent (including `php8.5`, `php8.5-fpm`, `php8.5-cli`,
    `php8.5-dev`, and all extension packages), keeping `php-pear`.
  - Change `phpenmod -v 8.4 ...` to `phpenmod -v 8.5 ...`.
  - Keep the `gd` FreeType/JPEG build-time verification unchanged so the build
    fails if either is missing.
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 7.1_

- [x] 3. Bump the MongoDB extension to a PHP 8.5-compatible release
  - In `Dockerfile-v4` layer 5, change `pecl install mongodb-2.3.3` to
    `pecl install mongodb-2.5.5`.
  - Update the extension-config path to `/etc/php/8.5/mods-available/mongodb.ini`
    and the enable command to `phpenmod -v 8.5 mongodb`.
  - Update the layer comment to note 2.5.x supports PHP 8.5 and 2.3.3 does not.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 8.2_

- [x] 4. Verify the v4 image builds and the toolchain is correct
  - Build locally: `docker build -f Dockerfile-v4 -t actions-runner-v4:local .`
  - Run the smoke check and confirm PHP 8.5.x is active, the `mongodb` extension
    loads, Composer reports `2.10.2`, and Node v22 is active:
    `docker run --rm actions-runner-v4:local bash -lc 'php -v; php -m | grep -i mongodb; composer --version; node -v'`
  - If `pecl install mongodb-2.5.5` fails to compile against PHP 8.5, resolve
    before proceeding (confirm the pinned patch supports 8.5).
  - _Requirements: 7.1, 7.2, 3.4_

- [x] 5. Confirm `Dockerfile-v3` still builds unchanged (regression)
  - Confirm `Dockerfile-v3` was not modified by this work (diff shows no
    changes) and that it still builds the PHP 8.4 image.
  - Confirm `Dockerfile` and `Dockerfile-v2` remain untouched.
  - _Requirements: 1.2, 1.3_

- [x] 6. Extend the CI workflow to select v3 or v4 from the git tag pattern
  - In `.github/workflows/docker-build.yml`, keep the single `on: push: tags:
    ['v*']` trigger (no `workflow_dispatch`, no manual input) and reuse the
    single QEMU + Buildx + Docker Hub login setup.
  - Add a second `docker/build-push-action@v5` step so there are two, each
    guarded by a step-level `if:` on `github.ref_name`:
    - v3 step: `if: ${{ !endsWith(github.ref_name, '-php8.5') }}`,
      `file: Dockerfile-v3`, existing tags
      `jayscgi/actions-runner:${{ github.ref_name }}` and `:latest`.
    - v4 step: `if: ${{ endsWith(github.ref_name, '-php8.5') }}`,
      `file: Dockerfile-v4`, tags `jayscgi/actions-runner:${{ github.ref_name }}`
      (already carries the `-php8.5` suffix) and `jayscgi/actions-runner:php8.5-latest`
      (confirm scheme per design open decision 2).
  - Verify exactly one step runs per tag push: `v1.2.3` → v3 only,
    `v1.2.3-php8.5` → v4 only.
  - Keep both steps multi-arch (`linux/amd64`, `linux/arm64`),
    `runs-on: self-hosted`, and the existing `DOCKER_USERNAME`/`DOCKER_PASSWORD`
    secrets; add no new secrets.
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 6.10, 6.11_

- [x] 7. Update project documentation and agent guidance
  - Update `AGENTS.md`: repo map and project overview to list `Dockerfile-v4`
    (PHP 8.5) and `Dockerfile-v3` (PHP 8.4) as both active; adjust the
    "only Dockerfile CI builds" wording; add v4 version pins (PHP 8.5, MongoDB
    2.5.5); keep `Dockerfile`/`Dockerfile-v2` deprecated and the "do not edit
    them" guardrail.
  - Update `.kiro/steering/*` build guidance: scope lists v3 and v4 as buildable
    active images, add v4 pins, add a v4 smoke check expecting PHP 8.5.
  - Do not mark v3 deprecated anywhere.
  - _Requirements: 1.2, 8.4_

- [x] 8. Final review against requirements
  - Re-read `requirements.md` and confirm each requirement is satisfied by the
    changes: new v4 exists, v3 untouched, PHP 8.5 + extensions, MongoDB 2.5.5,
    carry-over components identical, layer ordering preserved, CI builds both
    with non-colliding tags, build-time verification intact, docs updated.
  - _Requirements: all_
