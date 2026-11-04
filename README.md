# omerfsen.aicr

Ansible collection for [NVIDIA AI Cluster Runtime](https://docs.nvidia.com/aicr)
(AICR), NVIDIA's version-locked recipes for the GPU software stack on
Kubernetes: GPU Operator, DRA driver, NFD, NVSentinel, Nodewright, KAI
Scheduler, monitoring and more, in combinations NVIDIA has validated. It
installs a pinned `aicr` CLI, renders the recipe for your cluster into a
helmfile bundle, applies it, and validates the cluster against the recipe.
Rerun it any time; it only changes what differs.

AICR is a configuration generator, not a provisioner: you bring the cluster.
This collection pairs with [omerfsen.nvke](https://github.com/omerfsen/nvke),
which builds an NVKE (NVIDIA Kubernetes Engine) cluster, and has a playbook
for it, but the role works on any cluster AICR has a recipe for.

## Contents

| Name | Type | Does |
|---|---|---|
| `omerfsen.aicr.aicr` | role | Pinned `aicr` (and helmfile, helm-diff); recipe and bundle from an AICRConfig; `helmfile apply` and `aicr validate`, or an Argo CD bundle written into a GitOps checkout; `aicr_state: absent` removes the stack |
| `omerfsen.aicr.deploy` | playbook | The role on the `aicr_hosts` group (or `aicr_target`), for any cluster |
| `omerfsen.aicr.nvke` | playbook | AICR's `nvke` recipe on an omerfsen.nvke cluster, from its bootstrap host, with the overrides NVKE needs |
| `omerfsen.aicr.gitops` | playbook | The same recipe and overrides as an Argo CD Helm-chart bundle, rendered on this machine into a GitOps repository |

## Three ways to deploy AICR

AICR renders one recipe into bundles for Helm, helmfile, Argo CD, Flux,
Terraform or Fleet, and has an in-cluster operator in preview.

| Method | Here | When |
|---|---|---|
| helmfile, applied from the bootstrap host | `nvke` / `deploy` playbooks | No controller to run first. `helmfile apply` syncs only releases that differ (rerun `changed=0`), and its levels put CRDs in place before the charts that use them. The Helm bundle's `deploy.sh` upgrades everything on every run instead |
| Argo CD from Git (`argocd-helm` bundle) | `gitops` playbook | The cluster's state lives in a Git repository and Argo CD keeps it there. AICR's own guidance: a cluster that manages its GPU stack through Git keeps using the CLI to render (ADR-027) |
| The AICR Operator (`oci://ghcr.io/nvidia/charts/aicr-operator`) | not supported | See below |

**The AICR Operator** (Helm chart, AICR v1.2.0) runs AICR in the cluster
and rolls the stack out through Argo CD, with approvals and plan pinning,
from a `ClusterRuntime` resource. It is a preview (`v1alpha1`, no hardware
profile qualified yet), and it cannot run on the KVM lab:

- `ClusterRuntime.spec.intent` is required, and AICR's `nvke` recipe
  resolves an intent only with `accelerator: gb200`; the operator takes no
  custom recipe data (`--data`), and AICR records GeForce cards as
  `unknown-sku`, so there is no recipe it could select for an RTX 4080.
- It needs separate system and GPU node groups, Argo CD, and a default
  StorageClass for its in-cluster registry (NVKE ships none).
- It cannot adopt a stack the CLI installed.

## Why helmfile for the CLI path

- `helmfile apply` diffs every release and syncs only the ones that differ, so
  a rerun with nothing new reports `changed=0`.
- The bundle's release graph is split into levels, so CRDs from one level are
  in place before the next level's charts use them.
- No controller or state store to run first, unlike Flux or Terraform.

## Support matrix

| | Supported |
|---|---|
| AICR | v1.2.0, pinned (`aicr_version`, `aicr_sha256`) |
| helmfile / helm-diff | v1.8.2 / v3.15.15, pinned and checksum-verified |
| Helm | 3 or 4 on the target host, not installed by the role (tested with v4.2.4) |
| Argo CD | For the `argocd-helm` bundle: 2.13 or later (AICR), tested with v3.5.6 |
| Target host | Linux, amd64 or arm64, with helm, kubectl and the cluster's admin kubeconfig |
| Clusters | Any AICR service with a recipe (`aicr recipe --help`); the `nvke` playbook for omerfsen.nvke clusters |
| ansible-core | 2.16 or later |
| Tested | An NVKE v0.22.0 cluster from omerfsen.nvke on KVM (3 nodes, an RTX 4080 SUPER passed through to one). helmfile from the bootstrap host with Helm 4.2.4: 11 releases in 7m30s, `aicr validate` 3/3, rerun `changed=0` in 27s, `aicr_state=absent` removes them (rerun `changed=0`). Argo CD v3.5.6 (chart 10.11.6) from [omerfsen/gitops-public](https://github.com/omerfsen/gitops-public): the `gitops` playbook's bundle (rerun `changed=0`), 12 Applications Synced and Healthy, `aicr validate` 3/3, a deleted Deployment recreated in 37s. omerfsen.nvke's GPU tests (nvidia-smi, CUDA, TensorFlow, PyTorch, TensorRT, DCGM metrics) 6/6 on both |

## Component versions

What the `nvke` playbook installs: AICR v1.2.0's `nvke` recipe, with two charts
newer than AICR pins (NVSentinel v1.28.0 and cert-manager v1.20.2 upstream), set
through AICR's `--data` override in `playbooks/files/latest-charts`. Set
`aicr_nvke_data_src: ""` to use AICR's own pins.

| Release | Namespace | Version |
|---|---|---|
| nodewright-operator | nodewright | v0.20.0 |
| prometheus-operator-crds | monitoring | 28.0.1 |
| cert-manager | cert-manager | v1.21.3 |
| kube-prometheus-stack | monitoring | 84.4.0 |
| k8s-ephemeral-storage-metrics | monitoring | 1.19.2 |
| nfd | node-feature-discovery | 0.20.1 |
| gpu-operator | gpu-operator | v26.7.2 |
| kai-scheduler | kai-scheduler | v0.16.9 |
| nvidia-dra-driver-gpu | nvidia-dra-driver | 0.5.1 |
| nvsentinel | nvsentinel | v1.30.0 |
| prometheus-adapter | monitoring | 5.3.0 |

`dra-node-labeler`, the twelfth component, has no release of its own.

To change these versions after an AICR bump, or pin others, run
`tools/gen-latest-charts.sh <aicr checkout>`: AICR replaces a registry entry
wholesale, so the override carries the full entry with only the version changed.

## Quick start

### On an omerfsen.nvke cluster

Turn off omerfsen.nvke's own GPU Operator in the cluster's inventory, so the
two collections do not undo each other's values:

```yaml
# <nvke inventory>/group_vars/all/local.yml
nvke_gpu_operator: false
```

```shell
git clone https://github.com/omerfsen/aicr.git && cd aicr
make dev && source .venv/bin/activate
ansible-playbook -i ~/nvke/inventory/kvm playbooks/nvke.yml
# The KVM lab cluster (a consumer GPU, no ConnectX NICs):
ansible-playbook -i ~/nvke/inventory/kvm playbooks/nvke.yml -e @examples/nvke-kvm.yml
```

AICR's GPU Operator release has the same name and namespace as
omerfsen.nvke's, so it is upgraded in place, not installed beside it.

omerfsen.nvke's KVM inventory lists no VMs (its `kvm` playbook adds them at
run time), so the `nvke` playbook adds the bootstrap VM from the same
variables when the `nvke_bootstrap` group is empty. A static inventory that
lists the bootstrap host is used as it is.

**After that in-place upgrade, restart DCGM once.** AICR runs a standalone
DCGM host engine (`nvidia-dcgm`), which omerfsen.nvke's values did not. In
the upgrade it can start in the same second the driver container restarts
(the driver is rebuilt), come up without NVML, and the exporter then serves
no GPU metrics. `aicr validate` does not notice. One restart fixes it:

```shell
kubectl -n gpu-operator delete pod -l app=nvidia-dcgm
kubectl -n gpu-operator delete pod -l app=nvidia-dcgm-exporter
```

The `nvke` playbook adds what every NVKE v0.22 cluster on the reference node
image needs on top of AICR's `nvke` recipe:

- **Driver 615.71.09.** AICR pins 580.173.02, which has no Ubuntu 26.04 image.
- **The toolkit reads containerd's config file** (`RUNTIME_CONFIG_SOURCE=file`).
  NVKE ships containerd 2.3 with a version 3 `config.toml`; the toolkit's
  default reads `containerd config dump` (version 4), and its drop-in then
  stops containerd. AICR sets this in its GB200 NVKE recipe, not the generic one.
- **Only a GPU request reaches a GPU**
  (`ACCEPT_NVIDIA_VISIBLE_DEVICES_ENVVAR_WHEN_UNPRIVILEGED=false`), as in AICR's
  GB200 NVKE recipe.

- **Newer charts.** NVSentinel v1.30.0 and cert-manager v1.21.3 (see
  [Component versions](#component-versions)). Rendered for NVKE, not applied there
  yet; the same charts ran on kind.

More overrides go in `aicr_nvke_set` and `aicr_nvke_set_json`
(the base ones are in `playbooks/vars/nvke.yml`).

### NVSentinel alone on kind

`examples/kind-nvsentinel` cuts AICR's kind recipe down to NVSentinel, cert-manager
and Percona, with the quarantine step on and no GPU stack. It is the install behind
[nvidia-nvsentinel-mcp](https://github.com/omerfsen/nvidia-nvsentinel-mcp)'s fake
DCGM tests. Applied to a kind cluster (Kubernetes v1.36.4): NVSentinel v1.30.0 detected, cordoned
and drained on a simulated DCGM fault.

```shell
ansible-playbook playbooks/deploy.yml -i localhost, -c local -e aicr_target=localhost \
  -e @examples/kind-nvsentinel/vars.yml -e aicr_kubeconfig=<kind kubeconfig>
```

### With Argo CD from a GitOps repository

The `gitops` playbook renders the same recipe and overrides as an Argo CD
Helm chart (AICR's `argocd-helm` bundle) into a directory of a Git checkout.
It runs on this machine and needs no cluster access; it does not commit.

```shell
ansible-playbook playbooks/gitops.yml \
  -e aicr_gitops_dir=~/projects/gitops-public/nvke/aicr/lab -e @examples/nvke-kvm.yml
```

Commit the directory, then point one Application at it. The chart renders
one child Application per component, so the root sets
`deployer.includeRootApp: false`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: aicr-lab, namespace: argocd}
spec:
  project: default
  source:
    repoURL: https://github.com/omerfsen/gitops-public.git
    targetRevision: main
    path: nvke/aicr/lab
    helm:
      valuesObject: {deployer: {includeRootApp: false}}
  destination: {server: https://kubernetes.default.svc, namespace: argocd}
  syncPolicy: {automated: {prune: true, selfHeal: true}}
```

[omerfsen/gitops-public](https://github.com/omerfsen/gitops-public) holds
the lab's Argo CD values, this Application and the rendered bundle.

**Raise the nodes' inotify limit first.** With Argo CD's pods added, the GPU
node ran out of inotify instances (Ubuntu's default is 128 per user) and the
GPU device plugin crash-looped with `couldn't initialize inotify: too many
open files`. On every node:

```shell
printf 'fs.inotify.max_user_instances = 8192\nfs.inotify.max_user_watches = 524288\n' \
  | sudo tee /etc/sysctl.d/90-inotify.conf && sudo sysctl -p /etc/sysctl.d/90-inotify.conf
``` Validate
the cluster after Argo CD has synced with the `nvke` playbook and
`-e aicr_apply=false`: it renders and validates, and applies nothing.

### Removing the stack

```shell
ansible-playbook -i ~/nvke/inventory/kvm playbooks/nvke.yml -e aicr_state=absent
```

`helmfile destroy` removes the releases in reverse order. Helm leaves CRDs,
namespaces and objects that operators created (KAI's scheduler and its
admission webhooks). Before another installer takes over, remove them, the
webhooks first (a webhook whose service is gone blocks pod creation):

```shell
kubectl delete validatingwebhookconfiguration kai-podgroup-validation-v2alpha2 kai-queue-validation-v2 validating-kai-admission
kubectl delete mutatingwebhookconfiguration mutating-kai-admission
kubectl delete ns aicr-validation cert-manager gpu-operator kai-resource-reservation kai-scheduler \
  monitoring node-feature-discovery nodewright nvidia-dra-driver nvsentinel
kubectl get crd -o name | grep -E 'cert-manager.io|nvidia.com|kai.scheduler|nfd.k8s-sigs.io' | xargs kubectl delete
```

### Any other cluster

```yaml
# inventory.yml
all:
  children:
    aicr_hosts:
      hosts:
        admin1: {ansible_host: 10.0.10.5}
  vars:
    aicr_kubeconfig: /etc/kubernetes/admin.conf
    aicr_criteria: {service: eks, accelerator: h100, os: ubuntu, intent: training}
```

```shell
ansible-galaxy collection install omerfsen.aicr
ansible-playbook -i inventory.yml omerfsen.aicr.deploy
```

Render only, to read the bundle before anything is applied:

```shell
ansible-playbook -i inventory.yml omerfsen.aicr.deploy -e aicr_apply=false -e aicr_validate=false
# the bundle: /var/lib/aicr/bundle on the target host
```

`-e aicr_apply=false` alone renders and validates the cluster without
applying, for a stack another tool (Argo CD) deployed.

`--check` renders the bundle and runs `helmfile diff` instead of `apply`.

## How it works

1. **Tools.** `aicr`, helmfile and the helm-diff plugin, each from a pinned
   GitHub release with its SHA-256 checked.
2. **Render.** The role writes one AICRConfig (`aicr_criteria`, `aicr_set`,
   `aicr_scheduling`, the validation phases) and runs `aicr recipe` and
   `aicr bundle --deployer helmfile` (or `argocd-helm`) into an empty directory, with
   `aicr_set_json` as `--set-json` flags (the AICRConfig has no field for list
   or object overrides). AICR renders the same inputs to the same bytes, so
   the new bundle replaces the kept one in `/var/lib/aicr/bundle` only when
   they differ.
3. **Apply.** `helmfile apply --detailed-exitcode`: exit code 2 means it
   synced a release, and the task reports a change.
4. **Validate.** The role waits for the GPU Operator's ClusterPolicy, then runs
   `aicr validate`: a snapshot Job captures the cluster, and the recipe's
   checks (for `nvke`: platform health, GPU Operator health, DRA support) run
   as Jobs in `aicr-validation` and are deleted. The report is
   `/var/lib/aicr/validation.yaml`.

Every variable: [docs/variables.md](docs/variables.md).

## License and disclaimer

Licensed under the [Apache License 2.0](https://github.com/omerfsen/aicr/blob/main/LICENSE). The collection is provided
"AS IS", without warranties or conditions of any kind, and the authors accept
no liability for its use (sections 7 and 8 of the license). Test it on your
own systems before you rely on it.

This is an independent community project. It is not affiliated with, endorsed
or supported by NVIDIA. NVIDIA, AICR and NVKE are trademarks of their
respective owners.
