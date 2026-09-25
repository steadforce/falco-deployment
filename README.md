# Falco Deployment

![Falco logo](https://raw.githubusercontent.com/cncf/artwork/master/projects/falco/horizontal/color/falco-horizontal-color.svg)

Umbrella Helm chart that packages and configures [Falco](https://falco.org/) runtime security for our clusters.

> [!IMPORTANT]
> Never install the content of this repository on a cluster manually. Manifests are rendered by the
> [hydration workflow](#hydration) and applied exclusively by ArgoCD.

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Repository Layout](#repository-layout)
- [Environments](#environments)
- [Setup](#setup)
- [Rendering](#rendering)
- [Testing](#testing)
- [CI/CD](#cicd)
- [Dependency Updates](#dependency-updates)
- [Falco Specifics](#falco-specifics)
- [Troubleshooting](#troubleshooting)

## Overview

`Chart.yaml` declares the upstream [`falco`](https://github.com/falcosecurity/charts/tree/master/charts/falco) chart
from `https://falcosecurity.github.io/charts` as its only dependency, and `Chart.lock` pins the exact resolved
version. The umbrella chart has no templates of its own and its `values.yaml` is empty; all configuration is
layered on top of the subchart through root-level value files:

- `values-subchart-overrides.yaml` — shared overrides for every cluster: custom rules, the Kubernetes
  metadata collector, the modern eBPF driver, Prometheus metrics, a `ServiceMonitor`, and resource requests.
- `values-local.yaml` — additional overrides for local Kind clusters: debug logging, local-only rules, and
  zero CPU and memory requests.
- `values-sf-k8s04-dev.yaml` — additional override for `sf-k8s04-dev`, lowering the falco memory request.

Which value files apply to which cluster is controlled centrally by `helm-config.yaml`.

## Prerequisites

- [Docker](https://www.docker.com/) for the containerized commands in this guide.
- Optionally, the [SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace)
  workbench. It ships `helm`, `yq`, `kubectl`, `hetzner-k3s`, and `act`, so the workbench commands below run
  directly from its shell without a `docker run` wrapper.

All commands run from the repository root.

## Repository Layout

| Path                             | Purpose                                                              |
| -------------------------------- | -------------------------------------------------------------------- |
| `Chart.yaml`                     | Umbrella chart metadata and the `falco` dependency constraint.       |
| `Chart.lock`                     | Pinned `falco` version and digest; committed.                        |
| `values.yaml`                    | Umbrella chart defaults; intentionally empty.                        |
| `values-subchart-overrides.yaml` | Overrides shared by every cluster.                                   |
| `values-local.yaml`              | Additional overrides for local Kind clusters.                        |
| `values-sf-k8s04-dev.yaml`       | Additional overrides for `sf-k8s04-dev`.                             |
| `helm-config.yaml`               | Release name, namespace, and per-environment `apis` and `valueFiles`. |
| `tests/*_test.yaml`              | helm-unittest suites, one file per rendered resource.                |
| `scan-helm-capabilities.sh`      | Lists the API capabilities the chart checks for.                     |
| `.github/workflows/`             | Hydration, helm-unittest, and Trufflehog pipelines.                  |
| `README_WSL.md`                  | Running Falco on WSL with a custom kernel.                           |

`charts/`, `tests/__snapshot__/`, and `_local/` are gitignored and created locally.

## Environments

`helm-config.yaml` sets the release name and namespace (both `falco`) and defines one entry per environment:

| Environment     | Value Files                                                  |
| --------------- | ------------------------------------------------------------ |
| `local`         | `values-subchart-overrides.yaml`, `values-local.yaml`        |
| `sf-k8s01-dev`  | `values-subchart-overrides.yaml`                             |
| `sf-k8s02-dev`  | `values-subchart-overrides.yaml`                             |
| `sf-k8s03-dev`  | `values-subchart-overrides.yaml`                             |
| `sf-k8s04-dev`  | `values-subchart-overrides.yaml`, `values-sf-k8s04-dev.yaml` |
| `sf-k8s01-prod` | `values-subchart-overrides.yaml`                             |

All environments share the same `apis` list. To add an environment, add an entry under `environments`. If it
behaves like an existing one, reuse that entry's YAML anchor (for example `*environment`) instead of duplicating
the `apis` and `valueFiles` lists.

## Setup

Download the subchart pinned in `Chart.lock` into `charts/` after cloning and after every pull that changes
`Chart.lock`. `helm dependency build` resolves repositories by name, so the steps below first register every
HTTP(S) repository from `Chart.yaml`, the same way the pipeline does.

In the workbench:

```sh
 yq 'explode(.) | .dependencies[] | select(.repository == "http*") | .name + " " + .repository' Chart.yaml |
   while read -r name repo; do helm repo add --force-update "$name" "$repo"; done
 helm dependency build .
```

With Docker, `alpine/helm` ships `yq`, so both steps run in one container:

```sh
 docker run \
   -e HOME=/tmp \
   --entrypoint sh \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm -c '
     yq "explode(.) | .dependencies[] | select(.repository == \"http*\") | .name + \" \" + .repository" Chart.yaml |
       while read -r name repo; do helm repo add --force-update "$name" "$repo"; done &&
     helm dependency build .
   '
```

## Rendering

Render every environment from `helm-config.yaml` with the same `helm template` flags the hydration workflow uses.
Manifests are written to `_local/<environment>/falco/`. Run [Setup](#setup) first.

In the workbench:

```sh
 for environment in $(yq '.environments | keys[]' helm-config.yaml); do
   export environment
   helm template \
     -a "$(yq 'explode(.) | .environments.[env(environment)].apis | @csv' helm-config.yaml)" \
     -f "$(yq 'explode(.) | .environments.[env(environment)].valueFiles | @csv' helm-config.yaml)" \
     --include-crds \
     -n "$(yq 'explode(.) | .namespace' helm-config.yaml)" \
     --output-dir "_local/$environment" \
     --release-name \
     --skip-tests \
     "$(yq 'explode(.) | .releaseName' helm-config.yaml)" \
     .
 done
```

With Docker:

```sh
 docker run \
   -e HOME=/tmp \
   --entrypoint sh \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm -c '
     for environment in $(yq ".environments | keys[]" helm-config.yaml); do
       export environment
       helm template \
         -a "$(yq "explode(.) | .environments.[env(environment)].apis | @csv" helm-config.yaml)" \
         -f "$(yq "explode(.) | .environments.[env(environment)].valueFiles | @csv" helm-config.yaml)" \
         --include-crds \
         -n "$(yq "explode(.) | .namespace" helm-config.yaml)" \
         --output-dir "_local/$environment" \
         --release-name \
         --skip-tests \
         "$(yq "explode(.) | .releaseName" helm-config.yaml)" \
         . || exit 1
     done
   '
```

`--release-name` is a boolean flag that adds the release name to the output path; the release name itself is the
first positional argument.

## Testing

Chart behavior is covered by [helm-unittest](https://github.com/helm-unittest/helm-unittest) suites in
`tests/*_test.yaml`. They assert:

- the modern eBPF driver and the resulting privileged falco container,
- Falco metrics and the Prometheus metrics webserver endpoint,
- the debug log level on `local` and the default level elsewhere,
- the shared and the local-only custom rules files,
- the k8s-metacollector deployment,
- the `ServiceMonitor` and its `prometheus: cluster-monitoring` label,
- falco container resources on `local`, on `sf-k8s04-dev`, and on every other cluster,
- a snapshot of the local daemonset.

The tests render the subchart from `charts/`, so run [Setup](#setup) first, then:

```sh
 docker run \
   -e HELM_CACHE_HOME=/tmp/helm/.config \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   helmunittest/helm-unittest .
```

Append `-u` after the image name to rewrite the daemonset snapshot after an intentional change. To write the
results the way CI does, append `-t JUnit -o test-output.xml`; without `-t`, helm-unittest writes XUnit.

> [!NOTE]
> `tests/__snapshot__/` is gitignored and rebuilt locally. The snapshot catches broad side effects, but it
> proves nothing on its own: refreshing it silences a regression as easily as it records an intended change.
> Anything that must not change is covered by a direct assertion instead.

CI also lints the chart:

```sh
 docker run \
   -e HOME=/tmp \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm lint .
```

## CI/CD

All workflows call reusable workflows from
[steadforce/steadops-workflows](https://github.com/steadforce/steadops-workflows), pinned to `v4.2.0`.

| Workflow              | Trigger                           | Purpose                                              |
| --------------------- | --------------------------------- | ---------------------------------------------------- |
| `helm-hydration.yaml` | Push to `main`                    | Render manifests and open one PR per environment.    |
| `helm-unittest.yaml`  | Every push                        | Run helm-unittest and `helm lint`, notify MS Teams.  |
| `trufflehog.yaml`     | Push and pull request to `main`   | Scan the pushed commit range for leaked secrets.     |

Both Helm workflows register the HTTP(S) repositories from `Chart.yaml` and run `helm dependency build`, so the
versions in the committed `Chart.lock` are what gets tested and hydrated.

### Hydration

This repository implements a GitOps hydration pattern. For each environment in `helm-config.yaml`,
`helm-hydration.yaml` renders the chart into static manifests and commits them to a
`hydration-pull-request/<environment>-<version>` branch, where `<version>` is the `falco` version from
`Chart.lock`. It then opens a pull request against the long-lived `environments/<environment>` branch, which
ArgoCD deploys from. Patch releases share one branch per environment (the patch segment becomes `x`).

Because hydration runs without access to a live cluster, it mocks the cluster's available APIs through the
per-environment `apis` list in `helm-config.yaml`.

> [!WARNING]
> If a template uses conditional logic such as `if .Capabilities.APIVersions.Has "..."` and the required API is
> missing from `helm-config.yaml`, that resource is silently **not** rendered.

To find every API capability the chart and its subcharts check for, run `scan-helm-capabilities.sh`. It copies
the chart to a temporary directory, downloads and extracts all dependencies there, scans all `.yaml`, `.yml`,
and `.tpl` templates for `.Capabilities.APIVersions.Has`, and prints the API strings as a list for
`helm-config.yaml`. The script needs GNU `grep`, which the busybox-based `alpine/helm` image lacks, so run it in
the workbench:

```sh
 bash scan-helm-capabilities.sh
```

Or with Docker, using the workbench image:

```sh
 docker run \
   -e HOME=/tmp \
   --entrypoint bash \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   ghcr.io/steadforce/steadops/workbenches/k8s:main scan-helm-capabilities.sh
```

### Unit Tests And Notifications

`helm-unittest.yaml` runs the test suites, publishes the JUnit results, and lints the chart. On branches starting
with `renovate/`, it also posts the result to MS Teams:

- Successes go to the webhook in the `STEADOPS_HELM_RENOVATION_MS_TEAMS_WEBHOOK` secret.
- Failures go to the webhook in the `STEADOPS_HELM_RENOVATION_ERROR_MS_TEAMS_WEBHOOK` secret, or to the regular
  webhook when the error secret is not set.

### Running The Pipeline Locally

To run the GitHub Actions pipeline locally, start the workbench and run from the repository root:

```sh
 act
```

On first execution, `act` asks which flavor of its runner image to use; the default `medium` image is a good
starting point. Test result publishing and MS Teams notifications are skipped under `act`.

## Dependency Updates

[Renovate](https://docs.renovatebot.com/) keeps dependencies current, as configured in `renovate.json`:

- Minor and patch updates are merged automatically (squash).
- GitHub Actions and reusable workflow updates, including major and digest updates, are merged automatically.
- `falco` chart major and minor updates require a manual merge; `falco` patch updates are merged automatically.

To change the `falco` dependency by hand, edit its `version` in `Chart.yaml`, then regenerate `Chart.lock`:

```sh
 docker run \
   -e HOME=/tmp \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm dependency update .
```

Commit the new `Chart.lock` together with `Chart.yaml`, so that CI tests and hydrates the same version. See the
[Helm docs](https://helm.sh/docs/topics/charts/#chart-dependencies) for details.

## Falco Specifics

### Privileged Driver

`values-subchart-overrides.yaml` sets `driver.kind: modern-bpf` and `driver.modernEbpf.leastPrivileged: false`,
so the falco container runs with `privileged: true` rather than with the narrower `BPF`, `SYS_RESOURCE`,
`PERFMON`, and `SYS_PTRACE` capability set.

> [!WARNING]
> This is a deliberate trade-off, not an oversight: the least-privileged mode restricts what the modern eBPF
> driver can observe. Flipping it changes the container's privilege level cluster-wide, so treat it as a
> security decision. `tests/falco-daemonset_test.yaml` asserts the resulting `securityContext`, so neither
> direction changes silently.

### Drivers And WSL

Falco [downloads](https://download.falco.org/) a prebuilt driver for the host operating system it detects. WSL is
not supported out of the box and may require a [custom kernel](https://falco.org/blog/falco-wsl2-custom-kernel/);
see [`README_WSL.md`](README_WSL.md) for a step-by-step guide. More information is available in the
[falcosecurity/charts](https://github.com/falcosecurity/charts/tree/master/charts/falco#about-drivers) docs.

### Kind Clusters

Falco needs kernel access, so a Kind cluster needs `/dev` and `/var/run/docker.sock` mounted into its nodes. The
[required extra mounts](https://falco.org/docs/getting-started/learning-environments/#kind) are already part of the
[SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace).

## Troubleshooting

### `curl: (22) The requested URL returned error: 404` While Downloading The Driver

The prebuilt driver may not be available yet. Falco can't download it and fails to start; the logs show the
name of the file it tried to download. Check the
[prebuilt driver availability index](https://download.falco.org/driver/site/index.html?lib=3.0.1%2Bdriver&target=all&arch=all&kind=all)
to see whether one exists. The file Falco tries to download depends on the host's **kernel version** and
**operating system**. If you recently updated the host operating system, try booting with an older kernel.

### `Error: error opening device /host/dev/falco0`

Falco needs `/dev` and `/var/run/docker.sock` available in the Kind cluster. Pull the latest version of the
[SteadOps-Steadies-K8s-Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace),
remove your existing local cluster, and initialize it again.

### `Error: Could not create inotify handler` Or `Error: Too many files open`

This is a [Kind](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files) related
problem. Fix it with:

```sh
 sudo sysctl fs.inotify.max_user_watches=524288
 sudo sysctl fs.inotify.max_user_instances=512
```

Persist the setting across reboots:

```sh
 echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
 echo "fs.inotify.max_user_instances = 512" | sudo tee -a /etc/sysctl.conf
```
