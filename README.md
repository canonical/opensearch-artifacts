# OpenSearch Artifacts
[![Publish artifacts](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)

This repository contains the packaging metadata for all Canonical-distributed artifacts of [OpenSearch](https://opensearch.org/) — a community-driven, Apache 2.0-licensed open source search and analytics suite that makes it easy to ingest, search, visualize, and analyze data.

This branch packages OpenSearch 3.7.0 as three variants, each shipped both as a snap and as a rock (OCI image) built from that snap:

| Variant  | Package name          | Description                                                                                                                                    |
| -------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| standard | `opensearch`          | Upstream distribution without the `repository-s3`, `repository-gcs`, `repository-azure` and `prometheus-exporter` plugins                       |
| chiseled | `opensearch-chiseled` | Minimal variant: every bundled plugin except `opensearch-security` is removed, including `opensearch-knn` and `opensearch-performance-analyzer` |
| charmed  | `opensearch-charmed`  | Full bundled plugin set, for use by the [OpenSearch charms](https://github.com/canonical/opensearch-operator)                                   |

The snap and rock for a given variant share the same package name. Snaps are released to the `3/edge` channel of the Snap Store; rocks are released to the GitHub Container Registry as `ghcr.io/canonical/<name>:3.7.0-26.04_edge`.

## Repository structure

```
opensearch/
├── snaps/
│   ├── standard/    # opensearch snap
│   ├── chiseled/    # opensearch-chiseled snap
│   └── charmed/     # opensearch-charmed snap
└── rocks/
    ├── standard/    # opensearch rock
    ├── chiseled/    # opensearch-chiseled rock
    └── charmed/     # opensearch-charmed rock
```

Every artifact directory has its own README with install, build and test instructions. Each snap directory additionally ships a `CONTRIBUTOR.md` with the developer workflow, and a `spread/` suite run by `snapcraft test` (rocks are tested with `rockcraft test`).

## Publishing

A push to `3/edge` runs [publish.yaml](.github/workflows/publish.yaml), which:

1. records the snap revisions currently live on `3/edge`;
2. builds and releases every snap to `3/edge`;
3. waits until the new revisions are live on the store, for every architecture;
4. builds, tests, Trivy-scans and releases every rock, which stages its snap from that channel.

Both snaps and rocks are built for `amd64` and `arm64`.

## Licence

The packaging metadata in this repository is distributed under the Apache Software License, version 2.0. See [LICENSE](LICENSE), and the `licenses/` directory within each rock for the upstream OpenSearch licence.

## Trademark notice

OpenSearch is a registered trademark of Amazon Web Services. Other trademarks are property of their respective owners. OpenSearch is not sponsored, endorsed, or affiliated with Amazon Web Services.
