# Changelog

## 0.1.0 (2026-11-03)

### Features

* **collection:** add the aicr role and the deploy and nvke playbooks:
  a pinned aicr CLI, helmfile and helm-diff, an AICR recipe rendered into
  a helmfile bundle and applied only when it changed, then `aicr validate`
  ([#1](https://github.com/omerfsen/aicr/pull/1))
* **ci:** lint, galaxy-importer and build on every PR, Galaxy publish from
  a version tag ([#2](https://github.com/omerfsen/aicr/pull/2))
