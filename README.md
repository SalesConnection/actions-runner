# actions-runner

A custom GitHub Actions self-hosted runner image. It extends the
[`summerwind/actions-runner`](https://github.com/actions/actions-runner-controller)
base with a full PHP toolchain, the MongoDB PHP extension, Composer, and
Node.js (22 + 24 via nvm) so CI jobs for PHP/Node projects run without extra
per-job setup.

Published to Docker Hub as [`jayscgi/actions-runner`](https://hub.docker.com/r/jayscgi/actions-runner).

## What's included

Both lines are built on top of `summerwind/actions-runner:ubuntu-24.04`. The table below lists what is shared; the PHP version and MongoDB extension differ per line (see Image variants).

| Component | Version / Detail |
| --- | --- |
| Base image | `summerwind/actions-runner:ubuntu-24.04` |
| PHP | v3: 8.4-FPM + CLI; v4: 8.5-FPM + CLI (both via the `ondrej/php` PPA) |
| PHP extensions | bcmath, curl, exif, gd (FreeType + JPEG), intl, mbstring, gmp, redis, soap, sqlite3, xml, zip |
| MongoDB PHP extension | v3: 2.3.3; v4: 2.5.5 (built with `pecl`) |
| Composer | 2.10.2 (checksum-verified install) |
| Node.js | 22 (default) + 24, installed via nvm |
| SSH | `openssh-client` |
| Runs as | `runner` user (required by ARC) |
| Architectures | `linux/amd64`, `linux/arm64` |

## Image variants

> **Deprecation notice:** `Dockerfile` (v1) and `Dockerfile-v2` are deprecated
> and no longer maintained. Do not use them. `Dockerfile-v3` (PHP 8.4) and
> `Dockerfile-v4` (PHP 8.5) are both active and built by CI.

| File | Status |
| --- | --- |
| `Dockerfile-v3` | **Active (PHP 8.4)** - built and pushed by CI |
| `Dockerfile-v4` | **Active (PHP 8.5)** - built and pushed by CI |
| `Dockerfile-v2` | Deprecated |
| `Dockerfile` | Deprecated |

## Usage

### Pull the image

```bash
# PHP 8.4 (v3)
docker pull jayscgi/actions-runner:latest

# PHP 8.5 (v4)
docker pull jayscgi/actions-runner:php8.5-latest
```

### Quick local check

```bash
docker run --rm -it jayscgi/actions-runner:latest bash
```

### Deploy with Actions Runner Controller (ARC)

This image is designed to run as a self-hosted runner under
[Actions Runner Controller](https://github.com/actions/actions-runner-controller)
on Kubernetes. Reference it as the runner image in a `RunnerDeployment` -- use
`:latest` for the PHP 8.4 line or `:php8.5-latest` for the PHP 8.5 line:

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: actions-runner
  namespace: actions-runner-system
spec:
  replicas: 2
  template:
    spec:
      # GitHub org or repo this runner registers against
      organization: your-org
      # Use this custom image instead of the default ARC runner image
      image: jayscgi/actions-runner:latest
      imagePullPolicy: Always
      labels:
        - self-hosted
        - php
        - node
```

Optionally scale with a `HorizontalRunnerAutoscaler`:

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: actions-runner-autoscaler
  namespace: actions-runner-system
spec:
  scaleTargetRef:
    kind: RunnerDeployment
    name: actions-runner
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: PercentageRunnersBusy
      scaleUpThreshold: "0.75"
      scaleDownThreshold: "0.25"
```

Jobs then target the runner with matching labels:

```yaml
jobs:
  build:
    runs-on: [self-hosted, php]
```

## Building locally

Single-arch build (matches your host):

```bash
# v3 - PHP 8.4
docker build -f Dockerfile-v3 -t actions-runner:local .

# v4 - PHP 8.5
docker build -f Dockerfile-v4 -t actions-runner-v4:local .
```

Multi-arch build with Buildx (matches CI):

```bash
# v3 - PHP 8.4
docker buildx build \
  -f Dockerfile-v3 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner:local .

# v4 - PHP 8.5
docker buildx build \
  -f Dockerfile-v4 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner-v4:local .
```

## Release process

Releases are tag-driven, and the PHP line is selected from the git tag suffix.
A tag ending in `-php8.5` builds the PHP 8.5 line (v4); any other `v*` tag builds
the PHP 8.4 line (v3). Exactly one line is published per tag push.


```bash
# PHP 8.4 (v3)
git tag v1.2.3
git push origin v1.2.3

# PHP 8.5 (v4)
git tag v1.2.3-php8.5
git push origin v1.2.3-php8.5
```

CI then publishes to Docker Hub:

| Git tag pushed | Line built | Image tags published |
| --- | --- | --- |
| `v*` (no suffix, e.g. `v1.2.3`) | v3 / PHP 8.4 from `Dockerfile-v3` | `jayscgi/actions-runner:<tag>` and `:latest` |
| `v*-php8.5` (e.g. `v1.2.3-php8.5`) | v4 / PHP 8.5 from `Dockerfile-v4` | `jayscgi/actions-runner:<tag>` and `:php8.5-latest` |

The PHP 8.5 tags never overwrite the PHP 8.4 `:<tag>` or `:latest`, so existing
consumers of `:latest` are not disrupted.

## CI/CD

Defined in [`.github/workflows/docker-build.yml`](.github/workflows/docker-build.yml):

- **Trigger:** push of a `v*` tag
- **Runner:** `self-hosted`
- **Line selection:** a tag ending in `-php8.5` builds `Dockerfile-v4`; any other `v*` tag builds `Dockerfile-v3`
- **Steps:** QEMU + Buildx setup, Docker Hub login, multi-arch build/push of the selected Dockerfile
- **Required secrets:** `DOCKER_USERNAME`, `DOCKER_PASSWORD` (configured in the GitHub repo, not stored in this repo)

## Verifying the image

After building or pulling, confirm the toolchain inside the container:

```bash
# v3 - expect PHP 8.4
docker run --rm jayscgi/actions-runner:latest bash -lc '
  php -v
  php -m | grep -i mongodb
  php -r "var_dump(extension_loaded(\"gd\"));"
  composer --version
  node -v
  nvm ls
'
```

```bash
# v4 - expect PHP 8.5
docker run --rm jayscgi/actions-runner:php8.5-latest bash -lc '
  php -v
  php -m | grep -i mongodb
  php -r "var_dump(extension_loaded(\"gd\"));"
  composer --version
  node -v
  nvm ls
'
```

Expected v3: PHP 8.4, `mongodb` listed in modules, `gd` loaded, Composer 2.10.2, Node 22 active (with 24 available).
Expected v4: PHP 8.5, `mongodb` listed in modules, `gd` loaded, Composer 2.10.2, Node 22 active (with 24 available).

> Note: the base image's `ENTRYPOINT` is `["/bin/bash","-c"]`, so a bare
> `docker run --rm <image> bash -lc '...'` can silently produce no output.
> If a verification command prints nothing, override the entrypoint:
> `docker run --rm --entrypoint bash <image> -lc '...'`.
