# Falco Deployment

Umbrella Helm chart that packages and configures [Falco](https://falco.org/) runtime security
manifests for our clusters.

> [!IMPORTANT]
> Never install the content of this repository on a cluster manually. Manifests are rendered and
> applied exclusively by ArgoCD through the [Hydration Workflow](#hydration-workflow) described
> below.

## Overview

This chart declares `falco` as a Helm dependency (see `Chart.yaml`) and layers cluster-specific
configuration on top of it through root-level `values*.yaml` files:

- `values-subchart-overrides.yaml` — shared overrides applied to every cluster (custom rules,
  metrics, driver, collectors, resources).
- `values-local.yaml` — additional overrides applied only to local Kind development clusters
  (debug logging, zero resource limits, local-only rules).

Which value files apply to which cluster is controlled centrally by `helm-config.yaml`.

## Repository Structure

| Path                             | Purpose                                                            |
| --------------------------------- | ------------------------------------------------------------------ |
| `Chart.yaml` / `Chart.lock`       | Umbrella chart metadata and the pinned `falco` dependency version. |
| `values-subchart-overrides.yaml`  | Overrides shared by every cluster.                                 |
| `values-local.yaml`               | Additional overrides for local Kind clusters.                      |
| `helm-config.yaml`                | Per-environment `apis` and `valueFiles` used during hydration.     |
| `tests/*_test.yaml`               | helm-unittest suites, one file per rendered resource.              |
| `.github/workflows/`              | Hydration, helm-unittest, and Trufflehog secret-scan pipelines.     |
| `scan-helm-capabilities.sh`       | Static analysis tool described under [Dependency Scanning](#dependency-scanning). |

## Prerequisites

- [Docker](https://www.docker.com/) to run the containerized tooling used throughout this guide.
- Access to the [SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace)
  workbench for any command that needs `helm`, `yq`, `kubectl`, `hetzner-k3s`, or `act` together.

## Environments

Environments and their rendering configuration are defined in `helm-config.yaml`:

| Environment     | Value Files                                            |
| --------------- | ------------------------------------------------------- |
| `local`         | `values-subchart-overrides.yaml`, `values-local.yaml`  |
| `sf-k8s01-dev`  | `values-subchart-overrides.yaml`                       |
| `sf-k8s02-dev`  | `values-subchart-overrides.yaml`                       |
| `sf-k8s03-dev`  | `values-subchart-overrides.yaml`                       |
| `sf-k8s01-prod` | `values-subchart-overrides.yaml`                       |

Add a new environment by adding an entry under `environments` in `helm-config.yaml`. If the
environment shares behavior with an existing one, reuse the existing YAML anchor instead of
duplicating the `apis` and `valueFiles` lists.

## Chart Dependency

The version of the `falco` dependency is pinned in `Chart.yaml`. To bump it:

1. Update the `version` field under `dependencies` in `Chart.yaml`.
2. Refresh the downloaded chart:

   ```sh
    docker run \
      --rm \
      -e HOME=/tmp \
      -u $(id -u) \
      -v "$PWD:/apps" \
      -w /apps \
      alpine/helm dependency update
   ```

3. Commit the updated `Chart.yaml`, `Chart.lock`, and the refreshed `charts/` directory together.

See the [Helm docs](https://helm.sh/docs/topics/charts/#chart-dependencies) for more details.

## Rendering Manifests Locally

Run the following from inside the workbench, where `helm` and `yq` are available directly:

```sh
 helm dependency update && \
 for cluster in $(yq '.environments | keys[]' helm-config.yaml); do
   helm template \
     --include-crds \
     --output-dir "_local/$cluster" \
     --release-name "$(yq 'explode(.) | .releaseName // ""' helm-config.yaml)" \
     --skip-tests \
     -a "$(cluster=$cluster yq '.environments.[env(cluster)].apis | @csv' helm-config.yaml)" \
     -f "$(cluster=$cluster yq '.environments.[env(cluster)].valueFiles | @csv' helm-config.yaml)" \
     -n "$(yq 'explode(.) | .namespace // ""' helm-config.yaml)" \
     .
 done
```

Rendered manifests are written to `_local/<environment>` and are not tracked in git.

## Hydration Workflow

This repository implements a **GitOps Hydration Pattern**. The `helm-hydration.yaml` workflow
runs on every push to `main`, renders the Helm chart into static Kubernetes manifests for each
environment in `helm-config.yaml`, and opens automated pull requests targeting the corresponding
environment branch (for example `environments/local`, `environments/sf-k8s01-prod`).

### API Capabilities Configuration

Because hydration runs in CI without access to a live cluster, it must mock the cluster's
available APIs (CRDs) through the `apis` list per environment in `helm-config.yaml`.

> [!WARNING]
> If a template uses conditional logic such as `if .Capabilities.APIVersions.Has "..."` and the
> required API is missing from `helm-config.yaml`, that resource will silently **not** be
> rendered in the final manifest.

### Dependency Scanning

Use the provided static analysis tool to discover every API capability a chart (or its
dependencies) requires, so `helm-config.yaml` can be kept in sync:

```sh
 docker run \
   --entrypoint /bin/sh \
   --rm \
   -e HOME=/tmp \
   -u $(id -u) \
   -v "$PWD:/chart" \
   -w /chart \
   alpine/helm -c 'apk add --no-cache bash grep > /dev/null 2>&1 && bash scan-helm-capabilities.sh'
```

The script:

1. Downloads and extracts all chart dependencies locally.
2. Recursively scans all templates (`.yaml`, `.yml`, `.tpl`) in the chart and its subcharts.
3. Identifies every instance of `.Capabilities.APIVersions.Has`.
4. Outputs the exact list of API strings (groups and kinds) required in `helm-config.yaml`.

## Testing

Chart behavior is covered by [helm-unittest](https://github.com/helm-unittest/helm-unittest)
suites in `tests/*_test.yaml`, one per rendered resource. Run the full suite with:

```sh
 docker run \
   --rm \
   -e HELM_CACHE_HOME=/tmp/helm/.config \
   -e HOME=/tmp \
   -u $(id -u) \
   -v "$PWD:/apps" \
   -w /apps \
   helmunittest/helm-unittest .
```

## Running The GitHub Pipeline Locally

To run the GitHub Actions pipeline locally, start the workbench, `cd` into the folder containing
this `README.md`, and run:

```sh
 act
```

On first execution you're asked which flavor of the `act` image to use; the default `medium`
image is a good starting point.

## Falco In A Kind Cluster

Falco needs kernel access. If Falco runs inside a Kind cluster, additional cluster configuration
is needed.

`/dev` and `/var/run/docker.sock` have to be available to Falco. The
[extra Kind mounts required](https://falco.org/docs/getting-started/third-party/learning/#kind)
are already added in the
[SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace).

## The Falco Driver

Falco is configured to [download](https://download.falco.org/) a prebuilt driver based on the
host operating system it detects. WSL is not supported out of the box and may require a
[custom kernel](https://falco.org/blog/falco-wsl2-custom-kernel/) — see `README_WSL.md` for a
step-by-step guide. More information is available on the
[falcosecurity/charts](https://github.com/falcosecurity/charts/tree/master/falco#about-drivers)
page.

## Troubleshooting

### `curl: (22) The requested URL returned error: 404` while downloading the driver

The prebuilt module may not be available yet. Falco can't download the needed module and fails
to start; the module name it tried to download is visible in the logs. Check the
[prebuilt kernel module availability index](https://download.falco.org/driver/site/index.html?lib=3.0.1%2Bdriver&target=all&arch=all&kind=all)
to see whether one exists.
The version Falco tries to download depends on the installed **kernel version** and **operating
system** of the host. If you recently updated your host operating system, try booting with an
older kernel version.

### `Error: error opening device /host/dev/falco0`

Falco needs `/dev` and `/var/run/docker.sock` available in the Kind cluster. Pull the latest
version of the
[SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace),
remove your existing local cluster, and initialize it again.

### `Error: Could not create inotify handler` or `Error: Too many files open`

This is a [Kind](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)
related problem. Fix it with:

```sh
 sudo sysctl fs.inotify.max_user_watches=524288
 sudo sysctl fs.inotify.max_user_instances=512
```

Persist the setting across reboots:

```sh
 echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
 echo "fs.inotify.max_user_instances = 512" | sudo tee -a /etc/sysctl.conf
```
