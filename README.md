# OpenSearch Artifacts

[![Publish](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)
[![Lint](https://github.com/canonical/opensearch-artifacts/actions/workflows/lint.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/lint.yaml)

This repository contains the packaging metadata for all Canonical-distributed artifacts of [OpenSearch](https://opensearch.org/) and [OpenSearch Dashboards](https://opensearch.org/docs/latest/dashboards/). OpenSearch is a community-driven, open source search and analytics suite, and OpenSearch Dashboards is its visualization and user interface. Both are released under the Apache License, version 2.0.

This branch packages OpenSearch and OpenSearch Dashboards as variants, each shipped both as a snap and as a rock (OCI image) built from that snap.

## Artifacts

### OpenSearch

| Variant  | Package name          | Description                                                                                                                |
| -------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| standard | `opensearch`          | Full toolset: all bundled plugins except `repository-s3`, `repository-gcs`, `repository-azure` and `prometheus-exporter`   |
| chiseled | `opensearch-chiseled` | Minimal variant: same tools as standard, but ships only the `opensearch-security` plugin                                   |
| charmed  | `opensearch-charmed`  | Includes all bundled plugins                                                                                               |

### OpenSearch Dashboards

| Variant  | Package name                    | Description                                                    |
| -------- | ------------------------------- | -------------------------------------------------------------- |
| standard | `opensearch-dashboards`         | OpenSearch Dashboards with the `plugin` and `keystore` tools   |
| charmed  | `opensearch-dashboards-charmed` | Adds the Prometheus exporter (`exporter-daemon`)               |

The snap and rock for a given variant share the same package name.

See the `CONTRIBUTOR.md` and `README.md` of each artifact for build, test and development details.

## License

The packaging metadata in this repository is free software, distributed under the Apache Software License, version 2.0. See [LICENSE](LICENSE) for the full text.

The artifacts install and operate OpenSearch and OpenSearch Dashboards, which are also licensed under the Apache Software License, version 2.0.
