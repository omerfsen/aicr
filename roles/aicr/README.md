# omerfsen.aicr.aicr

Deploys an NVIDIA AI Cluster Runtime (AICR) recipe to a Kubernetes cluster
and checks the cluster against it.

- installs `aicr`, helmfile and the helm-diff plugin from pinned GitHub
  releases, checksum verified (helm must already be on the host);
- writes one AICRConfig from `aicr_criteria`, `aicr_set`, `aicr_scheduling`
  and the validation phases, and renders the recipe and a helmfile bundle into
  an empty directory (`aicr_set_json` goes in as `--set-json` flags);
- keeps the new bundle in `/var/lib/aicr/bundle` only when it differs from
  the last one (AICR renders the same inputs to the same bytes);
- `helmfile apply`, which syncs only the releases that differ, so a rerun
  reports `changed=0`; in check mode `helmfile diff` instead;
- waits for the GPU Operator's ClusterPolicy when the bundle has it, then
  runs `aicr validate`; the report is `/var/lib/aicr/validation.yaml`.

Runs on a host with helm, kubectl and the cluster's admin kubeconfig, such as
the NVKE bootstrap host. `aicr_apply: false` renders the bundle only.

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
