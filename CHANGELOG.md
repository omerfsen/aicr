# Changelog

## [0.2.0](https://github.com/omerfsen/aicr/compare/v0.1.0...v0.2.0) (2026-11-03)


### Features

* **aicr:** add argo cd gitops bundles and stack removal ([#5](https://github.com/omerfsen/aicr/issues/5)) ([ac507aa](https://github.com/omerfsen/aicr/commit/ac507aa8ca666a286355aab8d22083976939b6ec))

## 0.1.0 (2026-11-03)

### Features

* **collection:** add the aicr role and the deploy and nvke playbooks:
  a pinned aicr CLI, helmfile and helm-diff, an AICR recipe rendered into
  a helmfile bundle and applied only when it changed, then `aicr validate`
  ([#1](https://github.com/omerfsen/aicr/pull/1))
* **ci:** lint, galaxy-importer and build on every PR, Galaxy publish from
  a version tag ([#2](https://github.com/omerfsen/aicr/pull/2))
