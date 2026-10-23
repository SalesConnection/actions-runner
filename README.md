# actions-runner

A custom GitHub Actions self-hosted runner image. It extends the
[`summerwind/actions-runner`](https://github.com/actions/actions-runner-controller)
base with a full PHP 8.4 toolchain, the MongoDB PHP driver, Composer, and
Node.js (22 + 24 via nvm) so CI jobs for PHP/Node projects run without extra
per-job setup.

Published to Docker Hub as [`jayscgi/actions-runner`](https://hub.docker.com/r/jayscgi/actions-runner).

## What's included

Built from `Dockerfile-v3` on top of `summerwind/actions-runner:ubuntu-24.04`:

| Component | Version / Detail |
| --- | --- |
| Base image | `summerwind/actions-runner:ubuntu-24.04` |
| PHP | 8.4-FPM + CLI (via the `ondrej/php` PPA) |
| PHP extensions | bcmath, curl, exif, gd (FreeType + JPEG), intl, mbstring, gmp, redis, soap, sqlite3, xml, zip |
| MongoDB PHP driver | 2.3.3 (built with `pecl`) |
| Composer | 2.10.2 (checksum-verified install) |
| Node.js | 22 (default) + 24, installed via nvm |
| SSH | `openssh-client` |
| Runs as | `runner` user (required by ARC) |
| Architectures | `linux/amd64`, `linux/arm64` |

## Image variants

> **Deprecation notice:** `Dockerfile` (v1) and `Dockerfile-v2` are deprecated
> and no longer maintained. Do not use them. **`Dockerfile-v3` is the only
> supported image** and the only one wired into CI.

| File | Status |
| --- | --- |
| `Dockerfile-v3` | **Active** — built and pushed by CI |
| `Dockerfile-v2` | Deprecated |
| `Dockerfile` | Deprecated |

## Usage

### Pull the image

```bash
docker pull jayscgi/actions-runner:latest
```

### Quick local check

```bash
docker run --rm -it jayscgi/actions-runner:latest bash
```

### Deploy with Actions Runner Controller (ARC)

This image is designed to run as a self-hosted runner under
[Actions Runner Controller](https://github.com/actions/actions-runner-controller)
on Kubernetes. Reference it as the runner image in a `RunnerDeployment`:

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
        - php84
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
    runs-on: [self-hosted, php84]
```

## Building locally

Single-arch build (matches your host):

```bash
docker build -f Dockerfile-v3 -t actions-runner:local .
```

Multi-arch build with Buildx (matches CI):

```bash
docker buildx build \
  -f Dockerfile-v3 \
  --platform linux/amd64,linux/arm64 \
  -t actions-runner:local .
```

## Release process

Releases are tag-driven. Pushing a tag that matches `v*` triggers CI to build
and push the image:

```bash
git tag v1.2.3
git push origin v1.2.3
```

CI then publishes two tags to Docker Hub:

- `jayscgi/actions-runner:v1.2.3`
- `jayscgi/actions-runner:latest`

## CI/CD

Defined in [`.github/workflows/docker-build.yml`](.github/workflows/docker-build.yml):

- **Trigger:** push of a `v*` tag
- **Runner:** `self-hosted`
- **Steps:** QEMU + Buildx setup, Docker Hub login, multi-arch build/push of `Dockerfile-v3`
- **Required secrets:** `DOCKER_USERNAME`, `DOCKER_PASSWORD` (configured in the GitHub repo, not stored in this repo)

## Verifying the image

After building or pulling, confirm the toolchain inside the container:

```bash
docker run --rm jayscgi/actions-runner:latest bash -lc '
  php -v
  php -m | grep -i mongodb
  php -r "var_dump(extension_loaded(\"gd\"));"
  composer --version
  node -v
  nvm ls
'
```

Expected: PHP 8.4, `mongodb` listed in modules, `gd` loaded, Composer 2.10.2,
Node 22 active (with 24 available).
