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
| `omerfsen.aicr.aicr` | role | Pinned `aicr`, helmfile and helm-diff; recipe and helmfile bundle from an AICRConfig; `helmfile apply`; `aicr validate` |
| `omerfsen.aicr.deploy` | playbook | The role on the `aicr_hosts` group (or `aicr_target`), for any cluster |
| `omerfsen.aicr.nvke` | playbook | AICR's `nvke` recipe on an omerfsen.nvke cluster, from its bootstrap host, with the overrides NVKE needs |

## Why helmfile

AICR renders one recipe into bundles for Helm, helmfile, Argo CD, Flux,
Terraform or Fleet. This collection uses the helmfile bundle:

- `helmfile apply` diffs every release and syncs only the ones that differ, so
  a rerun with nothing new reports `changed=0`. The Helm bundle's `deploy.sh`
  upgrades every release on every run.
- The bundle's release graph is split into levels, so CRDs from one level are
  in place before the next level's charts use them.
- No controller or state store to run first, unlike Argo CD, Flux or
  Terraform. A GitOps bundle can be rendered from the same recipe later.

## Support matrix

| | Supported |
|---|---|
| AICR | v1.2.0, pinned (`aicr_version`, `aicr_sha256`) |
| helmfile / helm-diff | v1.8.2 / v3.15.15, pinned and checksum-verified |
| Helm | 3 or 4 on the target host, not installed by the role (tested with v4.2.4) |
| Target host | Linux, amd64 or arm64, with helm, kubectl and the cluster's admin kubeconfig |
| Clusters | Any AICR service with a recipe (`aicr recipe --help`); the `nvke` playbook for omerfsen.nvke clusters |
| ansible-core | 2.16 or later |
| Tested | An NVKE v0.22.0 cluster from omerfsen.nvke on KVM (3 nodes, an RTX 4080 SUPER passed through to one), from the bootstrap host with Helm 4.2.4: AICR v1.2.0's `nvke` recipe, 11 releases deployed in 7m30s (omerfsen.nvke's GPU Operator release upgraded in place), all 69 pods running, `aicr validate` 3/3 conformance checks pass, rerun `changed=0` in 27s; omerfsen.nvke's GPU tests (nvidia-smi, CUDA, TensorFlow, PyTorch, TensorRT, DCGM metrics) 6/6 pass |

## Component versions

What AICR v1.2.0's `nvke` recipe installs (`aicr recipe --service nvke`):

| Release | Namespace | Version |
|---|---|---|
| nodewright-operator | nodewright | v0.20.0 |
| prometheus-operator-crds | monitoring | 28.0.1 |
| cert-manager | cert-manager | v1.20.2 |
| kube-prometheus-stack | monitoring | 84.4.0 |
| k8s-ephemeral-storage-metrics | monitoring | 1.19.2 |
| nfd | node-feature-discovery | 0.20.1 |
| gpu-operator | gpu-operator | v26.7.2 |
| kai-scheduler | kai-scheduler | v0.16.9 |
| nvidia-dra-driver-gpu | nvidia-dra-driver | 0.5.1 |
| nvsentinel | nvsentinel | v1.28.0 |
| prometheus-adapter | monitoring | 5.3.0 |

`dra-node-labeler`, the twelfth component, has no release of its own.

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

More overrides go in `aicr_nvke_set` and `aicr_nvke_set_json`.

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
ansible-playbook -i inventory.yml omerfsen.aicr.deploy -e aicr_apply=false
# the bundle: /var/lib/aicr/bundle on the target host
```

`--check` renders the bundle and runs `helmfile diff` instead of `apply`.

## How it works

1. **Tools.** `aicr`, helmfile and the helm-diff plugin, each from a pinned
   GitHub release with its SHA-256 checked.
2. **Render.** The role writes one AICRConfig (`aicr_criteria`, `aicr_set`,
   `aicr_scheduling`, the validation phases) and runs `aicr recipe` and
   `aicr bundle --deployer helmfile` into an empty directory, with
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
