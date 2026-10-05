# OpenSearch-Snap
[![Build and Test](https://github.com/canonical/opensearch-snap/actions/workflows/ci.yaml/badge.svg)](https://github.com/canonical/opensearch-snap/actions/workflows/ci.yaml)
[![Publish](https://github.com/canonical/opensearch-snap/actions/workflows/release.yaml/badge.svg)](https://github.com/canonical/opensearch-snap/actions/workflows/release.yaml)

[//]: # (<h1 align="center">)
[//]: # (  <a href="https://opensearch.org/">)
[//]: # (    <img src="https://opensearch.org/assets/brand/PNG/Logo/opensearch_logo_default.png" alt="OpenSearch" />)
[//]: # (  </a>)
[//]: # (  <br />)
[//]: # (</h1>)

This is the snap for [OpenSearch](https://opensearch.org), a community-driven, Apache 2.0-licensed open source search and
analytics suite that makes it easy to ingest, search, visualize, and analyze data.


### Installation:
[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/opensearch)

or:
```
sudo snap install opensearch --channel=2/edge
sudo snap connect opensearch:process-control
```

### Environment configuration:
OpenSearch has a set of [pre-requisites](https://opensearch.org/docs/latest/opensearch/install/important-settings/) to function properly, they can be set as follows:
```
sudo sysctl -w vm.swappiness=0
sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w net.ipv4.tcp_retries2=5
```

### Starting OpenSearch:
#### Creating certificates:
```
# create the certificates
sudo snap run opensearch.setup          \
    --node-name cm0                     \
    --node-roles cluster_manager,data   \
    --tls-priv-key-root-pass root1234   \
    --tls-priv-key-admin-pass admin1234 \
    --tls-priv-key-node-pass node1234   \
    --tls-init-setup yes    # this creates the root and admin certs as well.
```

#### Starting OpenSearch:
```
sudo snap start --enable opensearch.daemon
```
`--enable` keeps the daemon enabled across reboots, refreshes and reverts: without it, it stays
stopped after them.

#### Creating the Security Index:
```
sudo snap run opensearch.security-init --tls-priv-key-admin-pass=admin1234
```
This is only needed once per cluster, to create its security index.

#### Reconfiguring OpenSearch:
Settings can also be written to `opensearch.yml` with `opensearch.setup`, like the upstream `-E`
option. The two forms cannot be combined in the same command:
```
sudo snap run opensearch.setup -Ecluster.name=logs -Enode.roles=cluster_manager,data
sudo snap restart opensearch.daemon
```
Run `sudo snap run opensearch.setup --help` for lists, removing a setting and more examples.

#### Replacing the certificates:
The certificates are generated with the scripts shipped in the snap, run in the snap environment:
```
CERTS=/var/snap/opensearch/current/etc/opensearch/certificates

# root CA and admin certificate (empty passwords generate unencrypted keys)
sudo snap run --shell opensearch.setup -c 'bash "$OPS_ROOT"/security/tls/self-managed-init.sh \
    --root-password "" --admin-password "" --root-subject "" --admin-subject "" \
    --rest-with-tls yes --target-dir "$OPENSEARCH_PATH_CERTS"'

# node certificate, signed by the root CA (--root-password of an encrypted root key)
sudo snap run --shell opensearch.setup -c 'bash "$OPS_ROOT"/security/tls/self-managed-node.sh \
    --name cm0 --root-password "" --node-password "" --node-subject "" \
    --rest-with-tls yes --target-dir "$OPENSEARCH_PATH_CERTS"'
```

Set the ownership and permissions of the generated files, so that the daemon (`snap_daemon`) can
read them and other users cannot read the private keys (anyone reading the admin key gets full admin
access), then restart the daemon:
```
sudo sh -c "chown snap_daemon:root $CERTS/* && chmod 660 $CERTS/*.pem $CERTS/*.srl"
sudo snap restart opensearch.daemon
```

**Do not run `opensearch.security-init` after a certificate rotation, even if the admin certificate
changed.** It uploads the local seed security configuration and can overwrite the users, roles and
role mappings created through the API. The existing security index remains valid after the
certificates are replaced, it does not need to be initialized again. See the upstream
[securityadmin documentation](https://docs.opensearch.org/latest/security/configuration/security-admin/).
After the restart, run the health checks below and check that an existing user created through the
API can still authenticate. If only the node certificate needs a renewal, only run the node
certificate command above with the existing root CA, set the permissions and restart the daemon.

#### Refreshing from a previous revision:
The node keeps its configuration, data and passwords, in the same locations. Only the heap dump path
of `jvm.options` is changed, from `data` to `/var/snap/opensearch/common/var/log/opensearch/java_heapdump.hprof`.

A daemon started with `snap start` without `--enable`, as the previous revisions documented, is
disabled: snapd keeps it stopped after a refresh or a revert. Start it with
`sudo snap start --enable opensearch.daemon`. On `snap revert`, the previous revision runs with the
configuration it had before the refresh.

Reverting to a revision shipping an older OpenSearch version is not possible once the newer one
started: OpenSearch refuses to downgrade the data of the node.

The previous revisions copy the OpenSearch home of the most recently modified other revision into
their own before a refresh. After refreshing from 2/stable to 2/edge then to this revision, the 2/edge
revision is left with the 2/stable libraries and does not start if reverted to. Restore them with:
```
REV=<revision reverted to>
sudo snap stop opensearch.daemon
for dir in lib modules plugins; do
    sudo rsync -a --delete --chown=snap_daemon:root "/snap/opensearch/${REV}/usr/share/opensearch/${dir}/" \
        "/var/snap/opensearch/${REV}/usr/share/opensearch/${dir}/"
done
sudo snap start --enable opensearch.daemon
```

### Heap dumps:
When the Java heap is exhausted, the JVM writes a dump to
`/var/snap/opensearch/common/var/log/opensearch/java_heapdump.hprof`, which requires enough free
disk space. The JVM keeps the first dump and does not overwrite it: move or remove it after the
investigation to allow another dump. Heap dumps can contain credentials and document contents:
keep them private. Refreshes only change the default `-XX:HeapDumpPath=data` of `jvm.options`, a
custom path is kept.

### Testing the OpenSearch setup:
You can either consume the REST API yourself or see if the below commands succeed, and you see that the tests `"PASSED"` successfully: 
```
# Check if cluster is healthy (green):
sudo snap run opensearch.test-cluster-health-green
> ....
> PASSED


# Check if node is up:
sudo snap run opensearch.test-node-up
> ....
> PASSED


# Check if the security index is well initialised:
sudo snap run opensearch.test-security-index-created
> ....
> PASSED
```

or:
```
sudo cp /var/snap/opensearch/current/etc/opensearch/certificates/node-cm0.pem ./
curl --cacert node-cm0.pem -XGET https://admin:admin@localhost:9200/_cluster/health?pretty
> {
  "cluster_name": "opensearch-cluster",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 1,
  "number_of_data_nodes": 1,
  "discovered_master": true,
  "discovered_cluster_manager": true,
  "active_primary_shards": 2,
  "active_shards": 2,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0,
  "delayed_unassigned_shards": 0,
  "number_of_pending_tasks": 0,
  "number_of_in_flight_fetch": 0,
  "task_max_waiting_in_queue_millis": 0,
  "active_shards_percent_as_number": 100
}
```

## License
The Opensearch Snap is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](https://github.com/canonical/opensearch-snap/blob/main/licenses/LICENSE-snap)
for more information.
