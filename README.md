# Falco
Repository containing manifests for falco installation. Never install the content of 
this repo on our clusters manually. This is all done by argocd.
## Dependencies
This chart pulls in `falco` as a dependency. The version
used is specified in `Chart.yaml` in the `dependencies` section.
If you change the version in there, you need to then run

    $ helm dependency update

in order to have the chart downloaded to the `charts` directory
and then also commit that new version alongside with the altered
`Chart.yaml` file.

See the [Helm docs](https://helm.sh/docs/topics/charts/#chart-dependencies)
for details.
## Falco in Kind cluster
Falco needs kernel access. If Falco runs inside a Kind cluster additional configuration 
to the cluster is needed.

### Configuration
`/dev` and `/var/run/docker.sock` have to be available for Falco. The configuration as extra mounts 
can be found [here](https://falco.org/docs/getting-started/third-party/learning/#kind).
These extra mounts are added in the [Steadies Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace).

## The Falco driver
Right now Falco is configured to [download](https://download.falco.org/) 
a prebuilt driver based on the information it can acquire about the host operating system. 
WSL is not supported and may require a [custom kernel](https://falco.org/blog/falco-wsl2-custom-kernel/).
More information can be found on the [github page](https://github.com/falcosecurity/charts/tree/master/falco#about-drivers).

## Possible Problems
### Trying to download a prebuilt falco module from ... curl: (22) The requested URL returned error: 404  
Sometimes the prebuilt module isn't available (yet). Falco can't download the needed module and isn't able to run.
The name of the module Falco tries to download should be visible in the logs.
You can look up the existence of a prebuilt kernel module [here](https://download.falco.org/driver/site/index.html?lib=3.0.1%2Bdriver&target=all&arch=all&kind=all). 
Which version Falco tries to download depends on the installed **kernel versions** and **operating system** on your **host**.  
If you recently updated your host operating system you can try to boot with an older kernel version.

### Error: error opening device /host/dev/falco0
Falco needs `/dev` and `/var/run/docker.sock` available in the Kind cluster. 
Try to pull the new version of the [Steadies Workplace](https://gitea.cloud01.intern.steadforce.com/Playground/SteadOps-Steadies-K8s-Workplace).
Remove your existing local cluster and initialize it again. The error should be fixed.

### Error: Could not create inotify handler or Error: Too many files open

Should only be a [Kind](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files) related problem. 
Use the following to fix the error.
```
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```
Persist the setting across reboots by adding it to /etc/sysctl.conf.

```
echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_instances = 512" | sudo tee -a /etc/sysctl.conf
```

## Render all manifests locally

```shell
 helm dependency update && \
 for cluster in $(yq '.environments | keys[]' helm-config.yaml); do
    helm template \
      -a "$(cluster=$cluster yq '.environments.[env(cluster)].apis | @csv' helm-config.yaml)" \
      -f "$(cluster=$cluster yq '.environments.[env(cluster)].valueFiles | @csv' helm-config.yaml)" \
      -n "$(yq 'explode(.) | .namespace // ""' helm-config.yaml)" \
      --output-dir _local/$cluster \
      --include-crds \
      --release-name "$(yq 'explode(.) | .releaseName // ""' helm-config.yaml)" \
      --skip-tests \
      .
 done
```

## Run GitHub pipeline locally

To run the GitHub pipeline in the local environment, start the workbench, cd into the folder containing this
`README.md` and execute the following command:

```shell
  act
```

On first execution, you're asked which flavour of the act image should be used. Using the default `medium`
is a good starting point.

## Hydration Workflow

This repository implements a **GitOps Hydration Pattern**.
The `helm-hydration.yaml` workflow is triggered by pushes to the `main` and `hydration` branches. It renders the Helm charts into static Kubernetes manifests and opens automated Pull Requests targeting the specific environment branches (e.g., `environments/local`, `environments/sf-k8s01-prod`) defined in `helm-config.yaml`.

### API Capabilities Configuration
Because the hydration process runs in a CI environment without access to a live Kubernetes cluster, it must **mock** the cluster's available APIs (CRDs). This is controlled via the `apis` list in `helm-config.yaml`.

If a chart (or its dependencies) uses conditional logic like `if .Capabilities.APIVersions.Has "..."`, and the specific API is missing from `helm-config.yaml`, the resource will **not** be rendered in the final manifest.

### Dependency Scanning
To ensure all conditional resources are correctly rendered, use the provided static analysis tool:

```bash
./scan-helm-capabilities.sh
```

> **Note:** The script requires `helm` to be available in your `PATH`. Since `helm` is not installed locally, run it via Docker:
> ```bash
> docker run --rm -u $(id -u) -v "$PWD:/chart" -w /chart \
>   --entrypoint /bin/sh alpine/helm \
>   -c 'apk add --no-cache bash grep > /dev/null 2>&1 && bash scan-helm-capabilities.sh'
> ```

This script:
1.  Downloads and extracts all chart dependencies locally.
2.  Recursively scans all templates (`.yaml`, `.yml`, `.tpl`) in your chart and its sub-charts.
3.  Identifies every instance of `.Capabilities.APIVersions.Has`.
4.  Outputs the exact list of API strings (Groups and Kinds) required in your `helm-config.yaml`.