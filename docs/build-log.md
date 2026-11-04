# Build log

Every step, command, failure and fix, written as it happens. Dead ends stay in.

## 2026-11-03: AICR on the NVKE cluster

### Goal

The GPU software stack on the NVKE management cluster from `omerfsen.nvke`
(three KVM node VMs, one RTX 4080 SUPER passed through to `nvke-cp-03`), from
NVIDIA AI Cluster Runtime (AICR) instead of the hand-picked GPU Operator
values in `omerfsen.nvke.gpu_operator`. Source of truth: docs.nvidia.com/aicr
and the tagged source at github.com/NVIDIA/aicr.

### What AICR is, and the release

AICR is a configuration generator: `aicr recipe` resolves criteria (service,
accelerator, OS, intent, platform) against NVIDIA's validated overlays into a
version-locked recipe, `aicr bundle` renders the recipe for a deployer, and
`aicr validate` checks a live cluster against it. It does not build clusters.

```shell
gh release list -R NVIDIA/aicr
# v1.2.0   Latest   2026-11-02   (commit 935e0746)
```

v1.2.0 is the first stable release with an `nvke` service. The binary was
checked against `aicr_checksums.txt`.

### What the nvke recipe gives this cluster

```text
$ aicr recipe --service nvke --os ubuntu --intent training
[INVALID_REQUEST] intent 'training' ... requires accelerator (valid: gb200);
os 'ubuntu' ... requires accelerator (valid: gb200)

$ aicr recipe --service nvke -o recipe.yaml
components=12 ... overlays=3
```

The nvke overlay is written for bare-metal GB200 trays (ConnectX-7 rails,
BlueField-3, InfiniBand); the only leaf below it is GB200 training. An RTX
4080 is not an AICR accelerator, so the cluster takes `--service nvke` with
no accelerator: 12 components (GPU Operator v26.7.2, DRA driver 0.5.1, NFD,
NVSentinel, Nodewright, KAI Scheduler, cert-manager, kube-prometheus-stack,
prometheus-adapter, the operator CRDs, ephemeral-storage metrics,
dra-node-labeler). Its validation: conformance checks `platform-health`,
`gpu-operator-health`, `dra-support`.

Read off the rendered GPU Operator values, three things do not fit:

- `driver.version: 580.173.02`. NGC has no `580.173.02-ubuntu26.04` image
  and the NVKE node image is Ubuntu 26.04.1 (the same finding as in
  omerfsen.nvke's build log). 615.71.09 has one and ran every GPU test there.
- No `toolkit.env`. AICR's GB200 NVKE leaf sets `RUNTIME_CONFIG_SOURCE=file`
  (NVKE's containerd 2.3 has a version 3 `config.toml`; the default source
  reports version 4 and the toolkit's drop-in stops containerd) and
  `ACCEPT_NVIDIA_VISIBLE_DEVICES_ENVVAR_WHEN_UNPRIVILEGED=false`. The generic
  nvke recipe has neither.
- The `nvsentinel-nic-health-monitor` mixin turns on NVSentinel's NIC health
  monitor. The VMs have no ConnectX NICs.

### Deployer

| Deployer | Verdict |
|---|---|
| helmfile | Chosen. `apply` syncs only releases that differ (idempotent reruns); levels order CRDs; nothing to run first |
| helm | `deploy.sh` runs `helm upgrade --install` for every release on every run |
| terraform | A state backend only for Helm releases; nothing else here uses Terraform |
| argocd / flux / fleet | A controller and a Git repository first; fine for a later GitOps phase, from the same recipe |

The AICRConfig file (`--config`) carries recipe criteria, `set` overrides,
scheduling and validation phases in one document. It has no field for list
values, so the toolkit `env` goes in as `--set-json`. Both together render
as expected:

```text
toolkit:
  enabled: true
  env:
    - name: RUNTIME_CONFIG_SOURCE
      value: file
    - name: ACCEPT_NVIDIA_VISIBLE_DEVICES_ENVVAR_WHEN_UNPRIVILEGED
      value: "false"
driver.version: 615.71.09
nicHealthMonitor.enabled: false
```

Two renders of the same inputs were byte-identical (`diff -r`), so the role
renders into an empty directory on every run and keeps the result only when
it differs.

### Toolchain on Helm 4

The bootstrap host has Helm v4.2.4 (from omerfsen.nvke). helmfile v1.8.2 and
helm-diff v3.15.15 (latest stable, both checksum-verified) with that exact
Helm: `helm plugin list` shows `diff 3.15.15 cli/v1 legacy`, and
`helmfile template` on the bundle pulled every chart (OCI from ghcr.io and
registry.k8s.io, HTTP repositories) and rendered 345 objects.

helm-diff is unpacked from its release archive into the plugin directory
rather than `helm plugin install`: the archive already has the binary, and its
install hook would download it again.

### The role

`omerfsen.aicr.aicr`: tools, render, `helmfile apply --detailed-exitcode`
(exit 2 = changed), wait for the ClusterPolicy, `aicr validate --config`.

Two things the argument spec taught:

- An option's `default:` in `meta/argument_specs.yml` is templated before the
  first task runs, so a URL default with `{{ aicr_arch }}` failed with
  `'aicr_arch' is undefined`. The URL defaults left the spec.
- The spec also templates the variables' values, so the same error came back
  from `defaults/main.yml`. `aicr_arch: amd64` in the defaults, overwritten
  by the role from `uname -m`, fixes both.

Render-only test on this host (`aicr_apply: false`, everything under a
scratch directory, as root):

```text
first run    ok=26 changed=7    # downloads, binaries, plugin, kept bundle
rerun        ok=25 changed=0
--check with driver 610.57.04   changed=1 (the compare step), kept bundle untouched
--check unchanged               changed=0
```

`ansible-lint --profile production` passes.

### On the cluster

Rebooted the hypervisor onto vfio-pci (`lspci -nnk -s 01:00`: `Kernel driver
in use: vfio-pci` for both functions; `gpu_passthrough.yml` rerun
`changed=0`), set `nvke_gpu_operator: false` in omerfsen.nvke's `local.yml`,
and started the cluster with its `kvm.yml` (1m50s, nothing to build).

The first run of `playbooks/nvke.yml` against omerfsen.nvke's KVM inventory:

```text
PLAY [NVIDIA AI Cluster Runtime on NVKE]
skipping: no hosts matched
```

That inventory lists no VMs; its `kvm` playbook adds them with `add_host` at
run time. The `nvke` playbook now starts with a play that adds the bootstrap
VM from `nvke_kvm_vms` (same key, same ProxyJump rule) when the
`nvke_bootstrap` group is empty.

```text
first run   localhost ok=1 changed=0   nvke-bootstrap ok=32 changed=8   real 7m33s
rerun       localhost ok=1 changed=0   nvke-bootstrap ok=31 changed=0   real 27s
```

All 11 releases `deployed`; `gpu-operator` went from revision 2 (omerfsen.nvke)
to 3, in place. 69 pods, all running. The ClusterPolicy is `ready` with
driver `615.71.09` and both toolkit variables; `nvke-cp-03` has
`nvidia.com/gpu: 1`. `aicr validate` (`/var/lib/aicr/validation.yaml`, CTRF):
3 tests, 3 passed (`platform-health`, `gpu-operator-health`, `dra-support`).
The DRA check notes the GPU is allocated through the device plugin
(`device-plugin-extended-resource`); the DRA driver's ResourceSlice is the
compute-domain one, and the full-GPU DRA subtest does not apply.

helmfile's diff found nothing to change on the rerun: no chart in the
bundle regenerates certificates or random values on every render.

omerfsen.nvke's GPU tests on the AICR stack:

```text
01-gpu-nvidia-smi            PASS         5s
02-gpu-cuda-vectoradd        PASS         5s
03-gpu-tensorflow            PASS        30s
04-gpu-pytorch               PASS        11s
05-gpu-tensorrt              PASS        10s
06-gpu-operator-metrics      FAIL         5s    no DCGM_FI_DEV_GPU_TEMP metric
```

The exporter's log: `MIG hierarchy unavailable because NVML is not loaded`,
and it reads from `DCGM_REMOTE_HOSTENGINE_INFO=nvidia-dcgm:5555`, a
standalone DCGM host engine AICR turns on (omerfsen.nvke's values did not).
That pod's log starts with `nvidia driver modules are not yet loaded,
invoking /usr/sbin/runc directly`: it started at 12:10:00, the second the
driver container restarted to rebuild the module for the upgrade, so the
runtime gave it no driver libraries and it never retried. It runs
privileged, so the toolkit's
`ACCEPT_NVIDIA_VISIBLE_DEVICES_ENVVAR_WHEN_UNPRIVILEGED=false` is not the
cause. Deleting the `nvidia-dcgm` pod, then the exporter's:
`NVML provider successfully initialized`, and

```text
06-gpu-operator-metrics      PASS         5s
```

A race of the in-place upgrade from omerfsen.nvke's release, documented in
the README with the two-pod restart; `aicr validate`'s
`gpu-operator-health` passes either way.

## 2026-11-03: Argo CD, removal, and the AICR Operator

### Research: what AICR offers besides the CLI

Read the v1.2.0 repository end to end (operator chart and docs, user and
integrator docs, recipes, validators, ADRs). Three ways to deploy:

- the CLI rendering a bundle for a deployer (what this collection did);
- the CLI rendering an Argo CD bundle into Git (AICR's ADR-027: a cluster
  that manages its GPU stack through Git keeps using the CLI);
- the AICR Operator, a Helm chart (`oci://ghcr.io/nvidia/charts/aicr-operator`,
  1.2.0) that runs AICR in the cluster and rolls out through Argo CD from a
  `ClusterRuntime` resource. Preview: `v1alpha1`, no hardware profile
  qualified.

The operator cannot run on this lab. `ClusterRuntime.spec.intent` is
required; AICR's `nvke` recipe resolves an intent only with
`accelerator: gb200` (`aicr recipe --service nvke --intent training` fails
coverage); the operator has no `--data` or catalog setting for custom
overlays; and AICR maps GeForce cards to `unknown-sku`, so discovery cannot
back an accelerator either. It also needs two distinct node groups, Argo CD,
a default StorageClass for its registry (NVKE ships none) and a cluster
without a CLI-installed stack (no adoption). So the GitOps path is the CLI's.

### The argocd-helm bundle at a repository subdirectory

The plain `argocd` bundle assumes the repository root (`path: .`,
`$values/007-gpu-operator/values.yaml`); there is no option for a
subdirectory. The `argocd-helm` bundle is a Helm chart whose child
Applications carry their values inline (`static/<component>.yaml` through
`.Files.Get`), so it works from any path. One root Application points at
`nvke/aicr/lab` with `deployer.includeRootApp: false`; `helm template` of the
chart that way gives 11 child Applications and no root.

The role got `aicr_deployer: argocd-helm` (render, then copy into
`aicr_gitops_dir` only when `diff -r` differs; no commit), `aicr_state:
absent`, and `aicr_owner`/`aicr_group` so the `gitops` playbook runs as the
user on the workstation. The NVKE overrides moved to `playbooks/vars/nvke.yml`
so both playbooks render the same stack. `gitops` rerun: `changed=0`, Git
checkout clean.

### Removing the CLI-installed stack

```text
TASK [List the installed Helm releases]  fatal: Error: unknown flag: --all
```

Helm 4 has no `helm list --all`; dropped. Then `aicr_state=absent`:
`helmfile destroy` in 57s, rerun `changed=0`. What Helm left: KAI's scheduler
pods and four admission webhooks (created by its operator from a CR), two
GPU Operator pods terminating, ten namespaces, 19 CRDs. Removed the webhooks
first (a mutating webhook on pods whose service is gone blocks pod creation),
then the namespaces and CRDs; nothing hung on finalizers.

### Argo CD from omerfsen/gitops-public

Latest Argo CD Helm chart: `argo-cd` 10.11.6, Argo CD v3.5.6 (2026-10-26;
v3.5.7 has no chart yet). AICR's CI pins 3.4.2 for the operator; the
argocd-helm bundle needs 2.13 or later. Installed with the chart and
`nvke/argocd/values.yaml` (one replica, insecure server behind
port-forward, no Dex, no notifications), then applied `nvke/apps/aicr-lab.yaml`
pointed at the branch until the repository's PR merges.

All 12 Applications Synced and Healthy, but the ClusterPolicy stayed
`notReady`:

```text
nvidia-device-plugin  failed to create FS watcher for /var/lib/kubelet/device-plugins/:
                      couldn't initialize inotify: too many open files
```

`nvke-cp-03`: `fs.inotify.max_user_instances = 128`, 145 instances in use
by root. Set 8192 instances and 524288 watches on all three nodes in
`/etc/sysctl.d/90-inotify.conf` (belongs in omerfsen.nvke's node
preparation), restarted the device plugin: ClusterPolicy `ready`,
`nvidia.com/gpu: 1`.

- `aicr validate` (the `nvke` playbook with `aicr_apply=false`): 3/3.
- GPU tests 6/6, DCGM metrics included: the DCGM race was the in-place
  upgrade's, a fresh install has none.
- Self-heal: deleted the prometheus-adapter Deployment; Argo CD recreated it,
  ready again in 37s.

## 2026-11-04: NVSentinel v1.30.0 and cert-manager v1.21.3

AICR v1.2.0 (the newest, and its main) pins NVSentinel v1.28.0 and cert-manager
v1.20.2, below NVSentinel's stated cert-manager v1.21 minimum. AICR's way to move
a version without a fork is an external registry passed as `--data`.

**Failure 1:** a registry with `apiVersion: aicr.nvidia.com/v1alpha1`:
`external registry.yaml has apiVersion ..., expected "aicr.run/v1beta1"`.

**Failure 2:** a registry entry with only the version and the chart coordinates:
`mixin "nvsentinel-nic-health-monitor" ... not in the component's registry-declared
mixinSafeOverridePaths`. An entry replaces AICR's wholesale, so every other field
was gone.

**Fix:** `tools/gen-latest-charts.sh` copies AICR's full entries and changes only
`helm.defaultVersion`. New role variable `aicr_data_src` copies a directory into
the render directory and passes `--data` to `recipe`, `bundle` and `validate`;
the `nvke` playbook defaults to `playbooks/files/latest-charts`.

**kind:** `examples/kind-nvsentinel` needs an overlay, since `--set` alone is
refused. In order: `global.mongodbStore.enabled` with a remediation stage ("Use a
remediation step mixin"); then the `nvsentinel-mongodb` component in the overlay
("sets identity/sourcing field type"), so its size goes in `aicr_set`; then
`--system-node-selector` is required; then the remediation mixin needs the
analyzer and metadata-collector, and metadata-collector needs NVML, which a kind
node has not. So the example uses `nvsentinel-quarantine`: detect, cordon, drain,
and no fault-remediation or janitor.

Tested with no cluster (`aicr_apply=false`): the `deploy` playbook renders the kind
and nvke bundles with nvsentinel v1.30.0 and cert-manager v1.21.3, a rerun is
`changed=0`, the `gitops` playbook renders `targetRevision: v1.30.0`, and the kind
bundle's values render against the v1.30.0 chart.

Not tested: applying any of this to a cluster, `aicr validate` with the new charts,
or the in-place upgrade from v1.28.0.
