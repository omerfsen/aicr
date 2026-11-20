# Changelog

## [0.4.0](https://github.com/omerfsen/aicr/compare/v0.3.0...v0.4.0) (2026-11-20)


### Features

* **aicr:** run AICR v1.3.0 with mixins, runtime metrics and an upgrade check ([#10](https://github.com/omerfsen/aicr/issues/10)) ([1b28a15](https://github.com/omerfsen/aicr/commit/1b28a15f1a7b1bc2ab90e7fd4ac9bb10e1e61bdc))

## [0.3.0](https://github.com/omerfsen/aicr/compare/v0.2.0...v0.3.0) (2026-11-04)


### Features

* **aicr:** run NVSentinel v1.30.0 and cert-manager v1.21.3 ([#8](https://github.com/omerfsen/aicr/issues/8)) ([05a2fd0](https://github.com/omerfsen/aicr/commit/05a2fd099841f7e2e305b40ee0f9145c48a90483))

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
