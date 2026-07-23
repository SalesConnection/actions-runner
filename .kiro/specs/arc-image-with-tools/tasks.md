# Tasks: ARC Docker Image with Pre-built Tools

## Implementation Tasks

- [x] 1. Create `Dockerfile-v3` with the base image and environment declarations
  - Add `FROM summerwind/actions-runner:ubuntu-24.04`
  - Add `ENV DEBIAN_FRONTEND=noninteractive NVM_DIR=/home/runner/.nvm`
  - Verify the file is named `Dockerfile-v3` in the repo root
  - **Requirement:** 1.1, 1.3, 8.3

- [x] 2. Add bootstrap layer (gnupg + software-properties-common)
  - `apt-get install gnupg software-properties-common` in a single `RUN`
  - Clean `apt` lists in the same layer
  - **Requirement:** 2.1, 2.3, 2.4

- [x] 3. Register the ondrej/php PPA
  - `add-apt-repository -y ppa:ondrej/php` followed by `apt-get update`
  - Verify this is a separate `RUN` layer from the system-library block
  - **Requirement:** 3.1

- [x] 4. Install system libraries
  - Install all 14 libraries in one `RUN`: `build-essential`, `libcurl4-openssl-dev`, `pkg-config`,
    `libssl-dev`, `libfreetype6-dev`, `libjpeg-turbo8-dev`, `libpng-dev`,
    `zlib1g-dev`, `libzip-dev`, `libonig-dev`, `libxml2-dev`, `libicu-dev`,
    `libgmp-dev`
  - Clean `apt` lists in the same layer
  - **Requirement:** 2.1, 2.2, 2.3, 2.4

- [x] 5. Install PHP 8.4-FPM and extensions
  - Install `php8.4`, `php8.4-fpm`, `php8.4-cli`, `php8.4-dev`, `php-pear`
  - Install extension packages: `php8.4-bcmath`, `php8.4-curl`, `php8.4-exif`,
    `php8.4-gd`, `php8.4-mbstring`, `php8.4-xml`, `php8.4-zip`, `php8.4-intl`,
    `php8.4-gmp`, `php8.4-soap`, `php8.4-sqlite3`, `php8.4-redis`
  - Run `phpinfo()` grep checks for FreeType and JPEG (fail build if absent)
  - Run `phpenmod -v 8.4 bcmath curl exif gd intl mbstring gmp redis soap sqlite3 xml zip`
  - `php8.4-sqlite3` provides `sqlite3`, `pdo`, and `pdo_sqlite` extensions
  - Clean `apt` lists in the same layer
  - **Requirement:** 3.1, 3.2, 3.3, 3.4, 3.5, 3.6

- [x] 6. Install MongoDB PHP extension 2.3.3 via pecl
  - Run `pecl install mongodb-2.3.3`
  - Write `extension=mongodb.so` to `/etc/php/8.4/mods-available/mongodb.ini`
  - Run `phpenmod -v 8.4 mongodb` to enable for CLI and FPM SAPIs
  - **Requirement:** 4.1, 4.2, 4.3

- [x] 7. Install nvm and pre-install Node.js 22 and 24
  - Run nvm install script with `HOME=/home/runner` override
  - Run `chown -R runner:runner /home/runner/.nvm`
  - Source nvm and run `nvm install 22`, `nvm install 24`, `nvm alias default 22`
  - Append nvm init lines to `/home/runner/.bashrc` and `/home/runner/.profile`
  - Write Node 22 bin directory to `/etc/environment` PATH for non-interactive shells
  - **Requirement:** 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8

- [x] 8. Add `USER runner` as the final instruction
  - Confirm no `RUN` steps follow that require root
  - **Requirement:** 1.3, 6.3

- [x] 9. Update `.github/workflows/docker-build.yml` to build `Dockerfile-v3`
  - Add `file: Dockerfile-v3` to the `docker/build-push-action` step
  - Confirm `platforms: linux/amd64,linux/arm64` is still present
  - **Requirement:** 7.3

- [x] 10. Local build verification
  - Build the image locally: `docker build -f Dockerfile-v3 -t arc-runner-v3-test .`
  - Verify `php --version` reports PHP 8.4
  - Verify `php -m | grep mongodb` reports the extension loaded
  - Verify `php -r "phpinfo();" | grep -i freetype` and `jpeg` both return output
  - Verify `node --version` reports v22.x
  - Verify `nvm --version` is accessible after `source ~/.nvm/nvm.sh`
  - Verify `nvm use 24 && node --version` reports v24.x
  - **Requirement:** 3.2, 3.3, 4.1, 5.5, 5.6

- [x] 11. Validate `Dockerfile-v3` correctness
  - Confirm the file starts with `FROM summerwind/actions-runner:ubuntu-24.04`
  - Confirm `ENV` declares both `DEBIAN_FRONTEND=noninteractive` and `NVM_DIR=/home/runner/.nvm`
  - Confirm bootstrap layer installs `gnupg` and `software-properties-common` and cleans apt lists in the same `RUN`
  - Confirm the ondrej/php PPA is registered in its own `RUN` step (separate from the system-library block)
  - Confirm all 13 system libraries are present in the system-libraries `RUN` step and apt lists are cleaned
  - Confirm PHP 8.4-FPM, `php8.4-dev`, `php-pear`, and all 12 extension packages are installed and `phpenmod` is called for each
  - Confirm the FreeType and JPEG `phpinfo()` grep checks are present in the PHP install layer
  - Confirm `pecl install mongodb-2.3.3`, the `.ini` file write, and `phpenmod mongodb` are all present
  - Confirm nvm install runs with `HOME=/home/runner`, `chown -R runner:runner /home/runner/.nvm` follows, both Node 22 and 24 are installed, default alias is 22, and `/etc/environment` is updated with the Node 22 bin path
  - Confirm `USER runner` is the last instruction in the file with no subsequent `RUN` steps
  - Run `docker build -f Dockerfile-v3 --check .` (BuildKit dry-run) if Docker is available, to catch syntax errors without a full build
  - Produce a pass/fail summary for each check above
  - **Requirement:** 1.1, 1.3, 2.1, 2.3, 2.4, 3.1, 3.2, 3.3, 4.1, 4.2, 4.3, 5.1, 5.5, 6.3
