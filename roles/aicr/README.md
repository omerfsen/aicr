# omerfsen.aicr.aicr

Deploys an NVIDIA AI Cluster Runtime (AICR) recipe to a Kubernetes cluster
and checks the cluster against it.

- installs `aicr`, helmfile and the helm-diff plugin from pinned GitHub
  releases, checksum verified (helm must already be on the host);
- writes one AICRConfig from `aicr_criteria`, `aicr_set`, `aicr_scheduling`
  and the validation phases, and renders the recipe and a helmfile bundle into
  an empty directory (`aicr_set_json` goes in as `--set-json` flags);
- composes opt-in mixins (`aicr_mixins`) through one more leaf overlay it
  writes, checks external data with `aicr recipe validate`, and keeps a recipe
  summary in `/var/lib/aicr/recipe-summary.txt`;
- `aicr_runtime_metrics` adds a workload's series and namespaces to the
  runtime Prometheus;
- when the new bundle differs from the kept one, runs `aicr upgrade-check`
  between them and keeps the report in `/var/lib/aicr/upgrade-check.txt`
  (`aicr_upgrade_check: enforce` stops unless every change is safe);
- keeps the new bundle in `/var/lib/aicr/bundle` only when it differs from
  the last one (AICR renders the same inputs to the same bytes);
- `helmfile apply`, which syncs only the releases that differ, so a rerun
  reports `changed=0`; in check mode `helmfile diff` instead;
- waits for the GPU Operator's ClusterPolicy when the bundle has it, then
  runs `aicr validate`; the report is `/var/lib/aicr/validation.yaml`. With
  `aicr_validate_evidence.cncf.cncfSubmission: true` it also writes the CNCF
  AI Conformance submission directory to `/var/lib/aicr/evidence`.

Runs on a host with helm, kubectl and the cluster's admin kubeconfig, such as
the NVKE bootstrap host. `aicr_apply: false` renders and validates without
applying; add `aicr_validate: false` to render only.

Two other modes:

- `aicr_deployer: argocd-helm` with `aicr_gitops_dir`: renders an Argo CD
  Helm-chart bundle into a directory of a Git checkout (no cluster access, no
  commit); Argo CD applies it from the repository.
- `aicr_state: absent`: `helmfile destroy` of the kept bundle. Helm leaves
  CRDs, namespaces and operator-created objects behind.

```yaml
- hosts: admin1
  become: true
  roles:
    - role: omerfsen.aicr.aicr
      vars:
        aicr_kubeconfig: /etc/kubernetes/admin.conf
        aicr_criteria: {service: eks, accelerator: h100, os: ubuntu, intent: training}
```

Variables: `ansible-doc -t role omerfsen.aicr.aicr`.
