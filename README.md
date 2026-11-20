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
| `omerfsen.aicr.aicr` | role | Pinned `aicr` (and helmfile, helm-diff); recipe and bundle from an AICRConfig, with opt-in mixins and runtime metrics; an upgrade check against the last bundle; `helmfile apply` and `aicr validate` (optionally with the CNCF AI Conformance submission), or an Argo CD bundle written into a GitOps checkout; `aicr_state: absent` removes the stack |
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

**The AICR Operator** (Helm chart, AICR v1.3.0) runs AICR in the cluster
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
| AICR | v1.3.0, pinned (`aicr_version`, `aicr_sha256`); the role needs 1.3.0 or later |
| helmfile / helm-diff | v1.8.2 / v3.15.15, pinned and checksum-verified |
| Helm | 3 or 4 on the target host, not installed by the role (tested with v4.2.4) |
| Argo CD | For the `argocd-helm` bundle: 2.13 or later (AICR), tested with v3.5.6 |
| Target host | Linux, amd64 or arm64, with helm, kubectl and the cluster's admin kubeconfig |
| Clusters | Any AICR service with a recipe (`aicr recipe --help`); the `nvke` playbook for omerfsen.nvke clusters |
| ansible-core | 2.16 or later |
| Tested | AICR v1.3.0 on an NVKE v0.22.0 cluster from omerfsen.nvke on KVM (3 nodes, an RTX 4080 SUPER passed through to one, VMs sized as in [Upgrading](#upgrading-from-omerfsenaicr-030-aicr-v120)): upgraded in place from this collection's 0.3.0 (AICR v1.2.0), `aicr validate` 3/3, rerun `changed=0` in 27s, omerfsen.nvke's GPU tests (nvidia-smi, CUDA, TensorFlow, PyTorch, TensorRT, DCGM metrics) 6/6; the extras example (a mixin and runtime metrics) applied, validated and rerun `changed=0`. AICR v1.2.0 (0.2.0): helmfile 11 releases in 7m30s, `aicr_state=absent`, and Argo CD v3.5.6 from [omerfsen/gitops-public](https://github.com/omerfsen/gitops-public) with self-heal; see [docs/build-log.md](docs/build-log.md) |

## Component versions

What the `nvke` playbook installs: AICR v1.3.0's `nvke` recipe, with cert-manager
v1.21.3 instead of AICR's v1.20.2 (below the v1.21 minimum of the NVSentinel AICR
pins), set through AICR's `--data` override in `playbooks/files/latest-charts`. Set
`aicr_nvke_data_src: ""` to use AICR's own pins.

| Release | Namespace | Version |
|---|---|---|
| nodewright-operator | nodewright | v0.21.0 |
| prometheus-operator-crds | monitoring | 28.0.1 |
| cert-manager | cert-manager | v1.21.3 |
| kube-prometheus-stack | monitoring | 84.5.0 (the operator and one Prometheus only) |
| k8s-ephemeral-storage-metrics | monitoring | 1.19.2 |
| nfd | node-feature-discovery | 0.20.1 |
| gpu-operator | gpu-operator | v26.7.2 |
| kai-scheduler | kai-scheduler | v0.16.9 |
| nktp | nktp | 0.2.0 |
| nvidia-dra-driver-gpu | nvidia-dra-driver | 0.5.1 |
| nvsentinel | nvsentinel | v1.31.0 |
| prometheus-adapter | monitoring | 5.3.0 |

`dra-node-labeler`, the thirteenth component, has no release of its own.

AICR v1.3.0 made NKTP, the NVKE Telemetry Pipeline, the stock telemetry
(ADR-026): OpenTelemetry collectors for metrics, logs, events and traces, with
kube-state-metrics, node-exporter and a metrics-server (NVKE ships none).
kube-prometheus-stack is cut down to the operator and one Prometheus that keeps
only the series prometheus-adapter needs, for 24 hours. NKTP's bundled backend,
`otel-lgtm`, is for evaluation only (one pod, `emptyDir`, anonymous Grafana
admin); for anything else turn it off and set the five backend endpoints, as in
AICR's [component catalog](https://github.com/NVIDIA/aicr/blob/v1.3.0/docs/user/component-catalog.md#nktp-telemetry-pipeline).

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

- **A newer cert-manager.** v1.21.3 (see [Component versions](#component-versions)).

More overrides go in `aicr_nvke_set` and `aicr_nvke_set_json`
(the base ones are in `playbooks/vars/nvke.yml`).

### Upgrading from omerfsen.aicr 0.3.0 (AICR v1.2.0)

Rerun the `nvke` playbook. Before anything is applied the role compares the
bundle the cluster runs with the new one (`aicr upgrade-check`) and shows the
report; on the lab it reads:

```text
COMPONENT              FROM     TO       VERDICT  NOTES
kube-prometheus-stack  84.4.0   84.5.0   manual   1 minor, 3 steps, ...
nktp                   -        0.2.0    -        new component, nothing to do
nodewright-operator    v0.20.0  v0.21.0  safe     1 minor, verified
nvsentinel             v1.30.0  v1.31.0  manual   1 minor, 5 steps
```

Run it with `-e aicr_upgrade_check=enforce` first to stop there and read the
steps (`/var/lib/aicr/upgrade-check.txt` on the bootstrap host). On the
`nvke` recipe:

- **NVSentinel:** the analyzer, remediation and reboot-image steps do not
  apply (none of them is composed). Its new CRDs are applied by the role
  before `helmfile apply` (`aicr_apply_crds`).
- **kube-prometheus-stack:** Grafana, Alertmanager, node-exporter,
  kube-state-metrics and the Prometheus history go; NKTP replaces them.
  After the upgrade, delete what Helm does not own:

  ```shell
  kubectl delete pvc --ignore-not-found -n monitoring prometheus-kube-prometheus-prometheus-db-prometheus-kube-prometheus-prometheus-0
  kubectl delete secret --ignore-not-found -n monitoring kube-prometheus-admission
  kubectl delete service --ignore-not-found -n kube-system kube-prometheus-kubelet
  ```

**The KVM lab needs bigger VMs.** NKTP requests about 14 GiB of memory across
the cluster, and AICR's validation agent a free CPU on the GPU node. On
omerfsen.nvke's default sizes (4 vCPU / 8 GiB nodes, 8 vCPU / 24 GiB GPU node)
NVSentinel's upgrade and then the validation Job stayed Pending. In the nvke
inventory:

```yaml
nvke_kvm_vm_sizes:
  nvke-cp-01: {vcpus: 6, memory_mb: 16384}
  nvke-cp-02: {vcpus: 6, memory_mb: 16384}
  nvke-cp-03: {vcpus: 12, memory_mb: 32768}
```

The sizes apply when a VM is created; resize a running lab one VM at a time
with `virsh shutdown`, `virsh setmaxmem/setmem/setvcpus --config`, `virsh start`.

If an upgrade fails half way (a release left `failed`), the rerun syncs that
release again: helm-diff sees no difference in a failed release, so
`helmfile apply` alone would leave it.

### Mixins, runtime metrics and CNCF evidence

`examples/nvke-kvm-extras.yml` turns on two AICR v1.3.0 features on the lab:

```shell
ansible-playbook -i ~/nvke/inventory/kvm playbooks/nvke.yml \
  -e @examples/nvke-kvm.yml -e @examples/nvke-kvm-extras.yml
```

- `aicr_mixins: [nvsentinel-observe, ...]` composes AICR's opt-in mixins
  (NVSentinel's object monitor, observe and remediation steps, external
  remediation, maintenance requests, CSP health monitors, ...). AICR has no
  flag for them; the role writes one more leaf overlay, with the recipe's
  criteria and the mixins, and checks that AICR applied it last. Some mixins
  need more: `nvsentinel-observe` brings a MongoDB datastore, which needs a
  system node selector (`aicr_scheduling`) and storage.
- `aicr_runtime_metrics: {namespaces: [...], series: [...]}`: since v1.3.0 the
  runtime Prometheus keeps only the series AICR's components query. This adds
  a workload's ServiceMonitors and series.
- `aicr_validate_evidence` is passed to AICR as `spec.validate.evidence`. With
  `cncf: {cncfSubmission: true, vendor: {...}}` validation also writes the CNCF
  AI Conformance submission directory to `/var/lib/aicr/evidence`. AICR first
  checks that the recipe's conformance checks can establish every applicable
  MUST requirement. AICR's generic `nvke` recipe declares three checks, so on
  the lab it is refused before any check runs (`the recipe's conformance checks
  cannot establish 7 applicable MUST requirement(s) of the v1.36 checklist`);
  NVIDIA publishes evidence for its NVKE GB200, GB300 and VR200 recipes.

### NVSentinel alone on kind

`examples/kind-nvsentinel` cuts AICR's kind recipe down to NVSentinel, cert-manager
and Percona, with the quarantine step on and no GPU stack. It is the install behind
[nvidia-nvsentinel-mcp](https://github.com/omerfsen/nvidia-nvsentinel-mcp)'s fake
DCGM tests. Applied to a kind cluster (Kubernetes v1.36.4): NVSentinel v1.30.0 detected, cordoned
and drained on a simulated DCGM fault. With AICR v1.3.0 it renders NVSentinel v1.31.0 (NKTP is off
in the example).

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
```

omerfsen.nvke 0.2.0 and later set these on every node (`nvke_node_sysctls`). Validate
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
  monitoring nktp node-feature-discovery nodewright nvidia-dra-driver nvsentinel
kubectl get crd -o name | grep -E 'cert-manager.io|nvidia.com|kai.scheduler|scheduling.run.ai|nfd.k8s-sigs.io|opentelemetry.io|monitoring.coreos.com' | xargs kubectl delete
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
   they differ. `aicr_mixins` adds one more leaf overlay to the external data
   (same criteria, based on the overlay the recipe ended on), `aicr recipe
   validate` checks any external data first, and `aicr query --summary` writes
   `/var/lib/aicr/recipe-summary.txt` (overlays, components, versions, checks).
3. **Upgrade check.** When the new bundle differs from the kept one,
   `aicr upgrade-check` compares them component by component from AICR's
   transition records: `safe`, `manual` (with the steps for this deployer),
   `unsafe` or `unknown`. The report is shown and kept in
   `/var/lib/aicr/upgrade-check.txt`; `aicr_upgrade_check: enforce` stops the
   run there unless every change is `safe`.
4. **Apply.** `helmfile apply --detailed-exitcode`: exit code 2 means it
   synced a release, and the task reports a change.
5. **Validate.** The role waits for the GPU Operator's ClusterPolicy, then runs
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
