# OpenSearch Snap
[![Publish artifacts](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)

This directory contains the packaging metadata for creating a snap of [OpenSearch](https://opensearch.org). The standard variant ships the upstream distribution without the `repository-s3`, `repository-gcs`, `repository-azure` and `prometheus-exporter` plugins.
For more information on snaps, visit [snapcraft.io](https://snapcraft.io/).

## Installing the Snap
The snap can be installed directly from the Snap Store. Follow the link below for more information.
<br>

[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/opensearch)

```bash
sudo snap install opensearch --channel=3/edge
```

The daemon relies on interfaces that are not auto-connected, and OpenSearch has a set of
[pre-requisites](https://opensearch.org/docs/latest/opensearch/install/important-settings/)
that must be set on the host:

```bash
sudo snap connect opensearch:log-observe
sudo snap connect opensearch:mount-observe
sudo snap connect opensearch:process-control
sudo snap connect opensearch:system-observe
sudo snap connect opensearch:sys-fs-cgroup-service

sudo sysctl -w vm.swappiness=0
sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w net.ipv4.tcp_retries2=5
```

[setup-dev-env.sh](setup-dev-env.sh) performs both steps for you. Alternatively,
let the daemon apply the kernel settings itself at startup:

```bash
sudo snap set opensearch set-sysctl-props=yes
```

## Interaction with the snap
By default the snap installs with the daemon disabled. Generate the certificates,
start the daemon, then initialise the security index:

```bash
# create the node, root and admin certificates
# node-roles must include both cluster_manager and data on a single-node
# cluster: a cluster_manager-only node cannot hold the security index shards
sudo snap run opensearch.setup \
    --node-name cm0 \
    --node-roles cluster_manager,data \
    --tls-priv-key-root-pass root1234 \
    --tls-priv-key-admin-pass admin1234 \
    --tls-priv-key-node-pass node1234 \
    --tls-init-setup yes

sudo snap start opensearch.daemon

# only needed once per cluster, or to rebuild the security index
sudo snap run opensearch.security-init --tls-priv-key-admin-pass=admin1234
```

The snap ships three checks that print `PASSED` on success:

```bash
sudo snap run opensearch.test-node-up
sudo snap run opensearch.test-cluster-health-green
sudo snap run opensearch.test-security-index-created
```

Or query the REST API directly:

```bash
sudo cp /var/snap/opensearch/current/etc/opensearch/certificates/node-cm0.pem ./
curl --cacert node-cm0.pem -XGET https://admin:admin@localhost:9200/_cluster/health?pretty
```

In addition to `daemon`, `setup` and `security-init`, this variant provides the
`cli`, `plugin`, `keystore`, `keytool`, `node`, `shard`, `upgrade`, `env`,
`env-from-file`, `opensearch-bin` and `performance-analyzer-agent` apps. Other
available commands can be found here: `snap info opensearch`

See [CONTRIBUTOR.md](CONTRIBUTOR.md) for the developer workflow, including live debugging.

## Building the Snap
### Clone Repository
```bash
git clone git@github.com:canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/snaps/standard
```
### Installing and Configuring Prerequisites
```bash
sudo snap install snapcraft --classic
sudo snap install lxd
sudo lxd init --auto
```
### Packing and Installing the Snap
```bash
snapcraft pack
sudo snap install ./opensearch*.snap --dangerous
```

Use `--dangerous` to skip signature verification for a locally built snap.
`--jailmode` is useful to confirm that nothing escapes `strict` confinement.

## Testing the Snap
This variant ships a [spread](https://github.com/canonical/spread) smoke suite
that sets up a single-node cluster, runs the bundled checks and asserts on the
shipped plugin set. It runs against a `craft` (LXD) backend on `ubuntu-26.04`:

```bash
snapcraft test
```

## License
The OpenSearch Snap is free software, distributed under the Apache Software
License, version 2.0. See [LICENSE](../../../LICENSE) for more information.
