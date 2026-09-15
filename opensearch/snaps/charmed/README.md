# OpenSearch Charmed Snap
[![Publish artifacts](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)

This directory contains the packaging metadata for creating a snap of [OpenSearch](https://opensearch.org) for use by the [OpenSearch charms](https://github.com/canonical/opensearch-operator). The charmed variant keeps the full bundled plugin set, and leaves cluster configuration, TLS and security initialisation to the charm, so it ships no test apps.
For more information on snaps, visit [snapcraft.io](https://snapcraft.io/).

## Installing the Snap
The snap can be installed directly from the Snap Store. Follow the link below for more information.
<br>

[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/opensearch-charmed)

```bash
sudo snap install opensearch-charmed --channel=3/edge
```

The daemon relies on interfaces that are not auto-connected, and OpenSearch has a set of
[pre-requisites](https://opensearch.org/docs/latest/opensearch/install/important-settings/)
that must be set on the host:

```bash
sudo snap connect opensearch-charmed:log-observe
sudo snap connect opensearch-charmed:mount-observe
sudo snap connect opensearch-charmed:process-control
sudo snap connect opensearch-charmed:system-observe
sudo snap connect opensearch-charmed:sys-fs-cgroup-service

sudo sysctl -w vm.swappiness=0
sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w net.ipv4.tcp_retries2=5
```

[setup-dev-env.sh](setup-dev-env.sh) performs both steps for you. Alternatively,
let the daemon apply the kernel settings itself at startup:

```bash
sudo snap set opensearch-charmed set-sysctl-props=yes
```

## Interaction with the snap
In a charm deployment the charm drives all of the below. To exercise the snap
by hand, generate the certificates, start the daemon, then initialise the
security index:

```bash
# create the node, root and admin certificates
# node-roles must include both cluster_manager and data on a single-node
# cluster: a cluster_manager-only node cannot hold the security index shards
sudo snap run opensearch-charmed.setup \
    --node-name cm0 \
    --node-roles cluster_manager,data \
    --tls-priv-key-root-pass root1234 \
    --tls-priv-key-admin-pass admin1234 \
    --tls-priv-key-node-pass node1234 \
    --tls-init-setup yes

sudo snap start opensearch-charmed.daemon

# only needed once per cluster, or to rebuild the security index
sudo snap run opensearch-charmed.security-init --tls-priv-key-admin-pass=admin1234
```

This variant ships no `test-*` apps, so verify through the REST API:

```bash
sudo cp /var/snap/opensearch-charmed/current/etc/opensearch/certificates/node-cm0.pem ./
curl --cacert node-cm0.pem -XGET https://admin:admin@localhost:9200/_cluster/health?pretty
```

Security initialisation can be skipped entirely, which is how the smoke test
runs a plain-HTTP single node:

```bash
sudo snap set opensearch-charmed init-security=no
```

In addition to `daemon`, `setup` and `security-init`, this variant provides the
`cli`, `plugin`, `keystore`, `keytool`, `node`, `shard`, `upgrade`, `env`,
`env-from-file`, `opensearch-bin` and `performance-analyzer-agent` apps. Other
available commands can be found here: `snap info opensearch-charmed`

See [CONTRIBUTOR.md](CONTRIBUTOR.md) for the developer workflow, including live debugging.

## Building the Snap
### Clone Repository
```bash
git clone git@github.com:canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/snaps/charmed
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
sudo snap install ./opensearch-charmed*.snap --dangerous
```

Use `--dangerous` to skip signature verification for a locally built snap.
`--jailmode` is useful to confirm that nothing escapes `strict` confinement.

## Testing the Snap
This variant ships a [spread](https://github.com/canonical/spread) smoke suite
that configures a single node with security disabled and asserts that the
cluster answers with the expected name. It runs against a `craft` (LXD) backend
on `ubuntu-26.04`:

```bash
snapcraft test
```

## License
The OpenSearch Charmed Snap is free software, distributed under the Apache
Software License, version 2.0. See [LICENSE](../../../LICENSE) for more information.
