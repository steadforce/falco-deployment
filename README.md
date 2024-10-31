# Falco
Repository containing manifests for falco installation. Never install the content of 
this repo on our clusters manually. This is all done by argocd.
## Dependencies
This chart pulls in `falco` and `falco-exporter` as a dependency. The version
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

## Render helm charts locally

The following command renders the charts like argo-cd does to validate the content.

### local

```
 helm template --release-name falco -n falco --include-crds --skip-tests \
  -a autoscaling.k8s.io/v1 \
  -a cert-manager.io/v1 \
  -a forecastle.stakater.com/v1alpha1 \
  -a keycloak.org/v1alpha1 \
  -a kiali.io/v1alpha1 \
  -a monitoring.coreos.com/v1 \
  -a networking.istio.io/v1beta1 \
  -a security.istio.io/v1beta1 \
  -f values-local.yaml \
  --output-dir _local . 
```

