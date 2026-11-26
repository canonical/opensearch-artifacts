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

For a locally built snap installed with `--dangerous`, connect the interfaces
normally connected by the store before starting the daemon:
`sys-fs-cgroup-service`, `log-observe`, `mount-observe` and `system-observe`, using
`sudo snap connect opensearch:<interface>` for each.

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

#### Setting OpenSearch settings:
As with the upstream `opensearch` command, any setting can also be written to
`opensearch.yml` with `-E <setting>=<value>`. This mode only changes settings:
it does not create certificates, and it cannot be mixed with the flags above.
```
sudo snap run opensearch.setup \
    -Ecluster.name=logs \
    -Enode.roles=cluster_manager,data \
    -Ediscovery.seed_hosts=10.0.0.1,10.0.0.2
```
- The value is written as a string. Like upstream, list settings accept comma
  separated values.
- A value in brackets is a YAML list, e.g. `-Enode.roles=[]` for a
  coordinating-only node. Quote entries that contain commas:
  `-Eplugins.security.nodes_dn='["CN=a,OU=x","CN=b,OU=x"]'`.
- An empty value removes the setting, e.g. `-Ehttp.port=`.

Restart the daemon to apply new settings: `sudo snap restart opensearch.daemon`.

The two interfaces can be used in separate invocations. `-E` changes only the
requested settings and never generates certificates or initializes security.
Legacy flags retain their historical defaults; use `--tls-self-managed no` when
keeping externally provisioned certificates. Repeating legacy certificate setup
renews the selected node certificate, so use `-E` for ordinary setting changes.
Neither interface starts the daemon automatically.

#### Starting OpenSearch:
```
sudo snap start opensearch.daemon
```

#### Creating the Security Index:
```
sudo snap run opensearch.security-init --tls-priv-key-admin-pass=admin1234
```

Run security initialization only when creating the cluster's security index or
deliberately replacing its configuration. It uploads the local seed files and
can overwrite API-created users, roles and mappings. Do not run it after a
certificate rotation or when joining an existing cluster.

#### Joining an existing cluster:

Use the target cluster's exact name, a compatible OpenSearch version, and the
plugins required by its indices. Provision node certificates and PKCS#8 keys
signed by a CA trusted by every node. Certificates must cover the actual hostnames
and IP addresses used by peers and clients; authorize the peer certificate DNs
in `plugins.security.nodes_dn`. Generating an independent CA on each node does
not establish trust between them.

A fresh, never-started 2.x installation has no standalone cluster identity. A
node that has already started as a standalone cluster must join using a new data
directory. Changing discovery settings cannot merge its cluster UUID or indices
into the target. Keep the original directory and migrate required data separately
using snapshot/restore or reindexing.

For an already-started node, stop it, save its configuration and create a fresh
directory. Run this block as one command; existing backup/data paths cause it to
stop rather than replace their contents:

```sh
sudo sh -eu <<'SH'
COMMON=/var/snap/opensearch/common
snap stop --disable opensearch.daemon
mkdir -m 700 "$COMMON/before-join"
cp -a /var/snap/opensearch/current/etc/opensearch "$COMMON/before-join/"
mkdir -m 770 "$COMMON/var/lib/opensearch-joined"
chown snap_daemon:root "$COMMON/var/lib/opensearch-joined"
SH
```

Provision the target-trusted certificates under
`/var/snap/opensearch/current/etc/opensearch/certificates`, owned by
`snap_daemon:root` with mode `660`. Set the HTTP and transport certificate, key,
CA paths and peer DNs with `opensearch.setup -E...`. Then configure discovery:

```sh
sudo opensearch.setup \
    -Ecluster.name=logs -Enode.roles=data,ingest \
    -Epath.data=/var/snap/opensearch/common/var/lib/opensearch-joined \
    -Ediscovery.seed_hosts=10.0.0.1,10.0.0.2,10.0.0.3 \
    -Ecluster.initial_cluster_manager_nodes= \
    -Eplugins.security.allow_default_init_securityindex=false &&
sudo snap start --enable opensearch.daemon
```

Use reachable cluster-manager addresses and retain multiple seeds for restart
resilience. For a never-started node, keep its default data path instead of
creating/selecting `opensearch-joined`. Authenticate with the target cluster's
credentials. Verify identical `cluster_uuid` values through `GET /`, expected
membership, healthy shard allocation and document access, using the target CA
and hostname verification. A running service alone does not prove a successful join.

Keep the selected data path across restarts, refreshes and reverts. If a join
fails, stop the daemon and restore the saved configuration to return to the
original standalone identity, retaining both data directories. Safely remove a
successfully joined node from its target before restoring its old configuration.

#### Renewing certificates:

To renew only this node's certificate with the existing CA, use the helper in
the snap environment. It accepts encrypted or unencrypted keys and derives SANs
from localhost, the hostname, reverse DNS and host IP addresses; `--sans` can
provide an explicit list. Keep peer node DNs configured during renewal.

```sh
sudo sh -eu <<'SH'
snap run --shell opensearch.setup -c 'bash "$OPS_ROOT/security/tls/self-managed-node.sh" \
    --name cm0 --root-password=root1234 --node-password=node1234 \
    --rest-with-tls=yes --target-dir="$OPENSEARCH_PATH_CERTS"'
CERTS=/var/snap/opensearch/current/etc/opensearch/certificates
chown snap_daemon:root "$CERTS/node-cm0.pem" "$CERTS/node-cm0-key.pem"
chmod 660 "$CERTS/node-cm0.pem" "$CERTS/node-cm0-key.pem"
snap restart opensearch.daemon
SH
```

Use the existing CA password and the actual node name. An empty node password
produces an unencrypted PKCS#8 key and removes obsolete PEM password settings.
For CA replacement in a multi-node cluster, coordinate trust and certificate
changes across all nodes. Verify that an existing API-created user and its data
remain accessible after rotation; do not rerun `security-init`.

#### PKCS12 and secure settings:

OpenSearch can use separate PKCS12 identity keystores and CA truststores for
transport and HTTP TLS. Put them under the configuration directory with
`snap_daemon:root` ownership and mode `660`. Configure each layer's
`plugins.security.ssl.<transport|http>.keystore_type=PKCS12`,
`keystore_filepath`, `keystore_alias`, `truststore_type=PKCS12` and
`truststore_filepath` with `-E`. Remove conflicting PEM path/password settings
using empty `-E` values. Store passwords with `opensearch.keystore add`, using
the corresponding `keystore_password_secure`, `keystore_keypassword_secure`
and `truststore_password_secure` setting names, then restart and verify TLS.

The managed Java truststore is a different store:
`/var/snap/opensearch/current/etc/opensearch/certificates/cacerts.p12`.
Use `opensearch.keytool` to manage it, keep its password as `changeit`, and name
custom aliases with the `opensearch-custom-` prefix. Each alias imports one
certificate; import multiple CAs separately. Refresh replaces `debian:` bundle
entries with the active JDK bundle and retains custom entries. Separately
configured TLS stores are not rewritten by this operation.

Unlike 3.x's shared configuration, 2.x keeps configuration, certificates and
keystores in revision-specific snap data. Revert restores the retained revision's
copies, including its custom CA entries and prior deletions. Check the intended
trust policy before restarting a reverted revision.

#### HTTP without TLS:

To use plain HTTP while retaining authentication and transport TLS, set
`-Eplugins.security.ssl.http.enabled=false` and restart. To deliberately disable
the security plugin, set `-Eplugins.security.disabled=true` and restart; this
also removes authentication. These are explicit operator choices. Installation
does not start or initialize a 2.x node in either mode.

#### Plugins, refreshes and reverts:

`opensearch.plugin` supports named plugins and custom ZIPs, including `file:` and
HTTP URLs. Plugins with `config/` and `bin/` contents use the same supported
installer. Removal retains plugin configuration unless `--purge` is requested.

Refresh replaces bundled plugins with the new distribution and retains compatible
custom plugins. Incompatible custom plugins are unloaded from the new revision;
their retained revision copies remain available for rollback. Operator settings
in `opensearch.yml` are preserved. Install compatible plugin versions and update
their settings before restarting: settings for an unavailable plugin can prevent
OpenSearch from starting. Snapshot/reindex plans must also account for indices
that require that plugin.

For 2.x, plugin configuration is revision-specific. Reverting restores that
revision's configuration, including configuration removed by a later purge.
This differs deliberately from 3.x's shared configuration and missing-directory
recovery. Historically removable bundled plugins remain removable in 2.x and
are restored by refresh; 3.x rejects their removal.

Before the first upgrade from an older 2.x snap, preserve a plugin inventory and
back up custom plugin/configuration files. Some older outgoing pre-refresh hooks
copy a retained revision's distribution over the active one; with several
retained revisions this can discard recently installed plugins before the new
hook runs. The incoming snap cannot prevent that outgoing operation.

Snap rollback is not an OpenSearch data-format downgrade. In particular, a node
started on 2.19.7 cannot subsequently start 2.19.4 against that data directory.
Prepare a compatible restore/reindex recovery plan before an engine upgrade.
After any revert, check `snap services opensearch`; 2.x reverts can leave the
daemon disabled, requiring `snap start --enable opensearch.daemon` when the
selected engine and data are compatible.

The native security tools are also available as
`opensearch.plugins-security-securityadmin`, `opensearch.plugins-security-hash`
and `opensearch.plugins-security-audit-config-migrater`, matching the 3.x app
names. The existing `security-init` command remains available for initial setup.

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
sudo cp /var/snap/opensearch/current/etc/opensearch/certificates/root-ca.pem ./
curl --cacert root-ca.pem -u admin:admin https://localhost:9200/_cluster/health?pretty
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
