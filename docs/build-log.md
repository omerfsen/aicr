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
