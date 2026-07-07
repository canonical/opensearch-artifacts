# opensearch-artifacts
This repository contains OpenSearch & OpenSearch Dashboards packaging artifacts used and creafted by Canonical. The repository includes snaps and rocks with different variants for OpenSearch and OpenSearch Dashboards. 


## Repository structure
```text
opensearch-artifacts/
├── LICENSE
├── README.md
└── opensearch/
    ├── snaps/
    |   ├── opensearch-charmed/ # Snap for Charmed OpenSearch Operator (Replicate upstream + required plugins for the snap)
    │   └── opensearch-chiseled/ # Chiseled Snap (Minimal plugins usage, e.g security plugin)
    │   └── opensearch/ # Standard Snap (Replicate the same list of plugins upstread OpenSearch uses)
    └── rocks/
    |   ├── opensearch-charmed/ # Rock for Charmed OpenSearch Operator 
    │   └── opensearch-chiseled/ # Chiseled Rock
    │   └── opensearch/ # Standard Rock
└── opensearch-dashboards/
    ├── snaps/
    |   ├── opensearch-charmed/ # Snap for Charmed OpenSearch Operator (Replicate upstream + required plugins for the snap)
    │   └── opensearch/ # Standard Snap (Replicate the same list of plugins upstread OpenSearch uses)
    └── rocks/
    |   ├── opensearch-charmed/ # Rock for Charmed OpenSearch Operator 
    │   └── opensearch/ # Standard Rock
```
## Getting started

This repository contains packaging artifacts for OpenSearch & OpenSearch Dashboards in both Snap and Rock formats.
To work on an artifact, clone the repository and change into the appropriate subdirectory.
Each artifact includes its own `README.md` and `CONTRIBUTING.md` with build and usage instructions.

Snaps (example):

```bash
git clone https://github.com/canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/snaps/<snap-name>
snapcraft pack
```

Rocks (example):

```bash
git clone https://github.com/canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/rocks/<rock-name>
rockcraft pack
```

## Project & Community

OpenSearch artifacts is an open source project that warmly welcomes community contributions, suggestions, fixes, and constructive feedback.

* Check our [Code of Conduct](https://ubuntu.com/community/ethos/code-of-conduct)
* Raise software issues or feature requests in [GitHub](https://github.com/canonical/opensearch-artifacts/issues)
* Report security issues through [LaunchPad](https://wiki.ubuntu.com/DebuggingSecurity#How%20to%20File)
* Meet the community and chat with us on [Matrix](https://matrix.to/#/#charmhub-data-platform:ubuntu.com)


## Contributing

If you want to contribute, see the `CONTRIBUTING.md` file in the relevant snap subdirectory for clone, build, lint, and test instructions.

## License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.