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
sudo snap install opensearch --channel=3/edge
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
The install hook sets up and starts a ready-to-use single node cluster:
- node `opensearch-<hostname>` in cluster `opensearch-cluster`, with the upstream default roles
- self-signed TLS certificates (root CA, admin and node) in
  `/var/snap/opensearch/common/etc/opensearch/certificates`, the node certificate valid for
  `localhost`, the hostname and the IP addresses of the host
- random passwords for all the internal users (`admin`, `kibanaserver`, ...), readable by root only:
  ```
  sudo cat /var/snap/opensearch/common/init_users_pass.yaml
  ```

#### Reconfiguring OpenSearch:
Settings are written to `opensearch.yml` with `opensearch.setup`, like the upstream `-E` option:
```
sudo snap run opensearch.setup -Ecluster.name=logs -Enode.roles=cluster_manager,data
sudo snap restart opensearch.daemon
```
Run `sudo snap run opensearch.setup --help` for lists, removing a setting and more examples.

#### Joining an existing cluster:

Installation creates a standalone cluster UUID, even before you store documents.
OpenSearch cannot merge that identity into another cluster by changing discovery
settings. Join using a new data directory and keep the original directory intact.
Its indices will **not** appear in the target cluster; migrate any required data
separately using snapshot/restore or reindexing.

This example adds a data/ingest node to an existing healthy cluster. Use a
compatible OpenSearch version, the target's exact cluster name, and reachable
cluster-manager transport addresses (port 9300 by default). Install any plugins
required by the target's indices, such as their analysis plugins. Before starting the
join, arrange a node certificate and matching PKCS#8 private key signed by a CA
trusted by the target. The certificate must cover this node's hostname/IP and be
authorized by `plugins.security.nodes_dn` on the other nodes. The joining node
must likewise trust and authorize the target's node certificates. Independent
per-node CAs generated on installation do not establish this trust.

First stop the joining node, save its current configuration (including its TLS
files), and create a fresh data directory. Run the block as one command: `sh -e`
stops on failure, and `mkdir` without `-p` refuses an existing backup or data path,
including a symlink. Do not remove an existing directory to make it succeed.

```sh
sudo sh -eu <<'SH'
COMMON=/var/snap/opensearch/common
snap stop --disable opensearch.daemon
mkdir -m 700 "$COMMON/before-join"
cp -a "$COMMON/etc/opensearch" "$COMMON/before-join/"
mkdir -m 770 "$COMMON/var/lib/opensearch-joined"
chown snap_daemon:root "$COMMON/var/lib/opensearch-joined"
SH
```

Provision the target-trusted TLS files under
`/var/snap/opensearch/common/etc/opensearch/certificates`, owned by
`snap_daemon:root` with mode `660`. Configure the transport and HTTP certificate,
key and trusted-CA paths and the peer node DNs using `opensearch.setup -E...`.
Keep private keys out of shared directories. Do not generate a new independent
root CA or run `opensearch.security-init`: the target cluster already has its
security index. See the upstream [TLS configuration](https://docs.opensearch.org/latest/security/configuration/tls/)
for the certificate settings and requirements.

With TLS configured, replace `logs` and `10.0.0.1` below with the target cluster's
name and seed address, then configure and start the joining node:

```sh
sudo snap run opensearch.setup \
    -Ecluster.name=logs -Enode.roles=data,ingest \
    -Epath.data=/var/snap/opensearch/common/var/lib/opensearch-joined \
    -Ediscovery.seed_hosts=10.0.0.1 \
    -Ecluster.initial_cluster_manager_nodes= \
    -Eplugins.security.allow_default_init_securityindex=false &&
sudo snap start --enable opensearch.daemon
```

Authenticate using the **target cluster's** credentials; this node's install-time
passwords belong to its retained standalone cluster. Query `GET /` on both nodes
and confirm identical `cluster_uuid` values, then check `GET /_cluster/health`
and `GET /_cat/nodes?v` for the expected membership and healthy shard allocation.
Use the target CA with your client and retain hostname verification. A successful
TCP connection or a running service alone does not establish that the join worked.

Keep the selected `path.data` for subsequent starts, refreshes and reverts. Do not
repeat the fresh-directory step on restart. If the join fails, stop the daemon
and restore the saved configuration and certificates from `before-join/opensearch`
to return to the original data path and standalone UUID. Keep both data directories;
do not restore the original configuration on a successfully joined node until it
has been safely removed from the target cluster. For background, see upstream
[cluster bootstrapping](https://docs.opensearch.org/latest/tuning-your-cluster/discovery-cluster-formation/bootstrapping/).

#### Replacing the certificates:
The following replaces the root CA, admin certificate and node certificate for the
single-node setup above. Clients must trust the new root CA before reconnecting.
For a multi-node cluster, coordinate CA trust and certificate replacement across
all nodes; do not generate an independent root CA on each node.

The certificates are generated with the scripts shipped in the snap, run in the snap environment:
```
CERTS=/var/snap/opensearch/common/etc/opensearch/certificates

# root CA and admin certificate (empty passwords generate unencrypted keys)
sudo snap run --shell opensearch.setup -c 'bash "$OPS_ROOT"/security/tls/self-managed-init.sh \
    --root-password "" --admin-password "" --root-subject "" --admin-subject "" \
    --rest-with-tls yes --target-dir "$OPENSEARCH_PATH_CERTS"'

# node certificate, signed by the root CA
sudo snap run --shell opensearch.setup -c 'bash "$OPS_ROOT"/security/tls/self-managed-node.sh \
    --name "opensearch-$(hostname)" --root-password "" --node-password "" --node-subject "" \
    --rest-with-tls yes --target-dir "$OPENSEARCH_PATH_CERTS"'
```

**The generated files are owned by root and readable by all users: you must set their ownership
and permissions**, so that the daemon (`snap_daemon`) can read them and other users cannot read the
private keys (anyone reading the admin key gets full admin access):
```
sudo sh -c "chown snap_daemon:root $CERTS/* && chmod 660 $CERTS/*.pem $CERTS/*.srl"
```

Then restart the daemon to load the new certificates and settings:
```
sudo snap restart opensearch.daemon
```

**Do not run `opensearch.security-init` after certificate rotation, even if the
admin certificate changed.** It uploads the local seed security configuration and
can overwrite users, roles and role mappings created through the API. The existing
security index remains valid after certificate replacement. It does not need to
be initialized again. See the upstream [securityadmin documentation](https://docs.opensearch.org/latest/security/configuration/security-admin/)
for details about configuration uploads.

After startup, run the health checks below and verify that an existing API-created
user can still authenticate and access its permitted indices using the new CA.
If only the node certificate needs renewal, run only the node-certificate command
above with the existing CA, fix the file permissions, and restart the daemon.

### Java's trusted CAs

The writable Java truststore is
`/var/snap/opensearch/common/etc/opensearch/certificates/cacerts.p12`.
Refresh replaces its bundled CA entries with those shipped by the snap's OpenJDK;
revert restores the previous revision's bundled CAs when the daemon starts.
The `debian:` alias prefix belongs to the bundle. Manual changes or deletions
under that prefix are overwritten on refresh. Name custom CAs with the
`opensearch-custom-` prefix. Pass the CA through stdin: the shell reads the file,
so the snap needs no access to its location:

```sh
cat company-root.pem | sudo opensearch.keytool -importcert -noprompt \
    -alias opensearch-custom-company-root \
    -keystore /var/snap/opensearch/common/etc/opensearch/certificates/cacerts.p12 \
    -storepass changeit
sudo snap restart opensearch.daemon
```

You can also omit `cat company-root.pem |` and append `< company-root.pem`, or
`<<< "$(cat company-root.pem)"` in Bash. The shell supplies the PEM through stdin;
keytool does not accept literal PEM contents as a positional argument. Use
`-noprompt` for these stdin forms because stdin carries the certificate, not
answers to keytool's confirmation prompt.

Alternatively, copy the file into the snap's common directory first and import it with `-file`:

```sh
sudo cp company-root.pem /var/snap/opensearch/common/
sudo opensearch.keytool -importcert -noprompt \
    -alias opensearch-custom-company-root \
    -file /var/snap/opensearch/common/company-root.pem \
    -keystore /var/snap/opensearch/common/etc/opensearch/certificates/cacerts.p12 \
    -storepass changeit
sudo snap restart opensearch.daemon
```

To remove a custom CA, use the same keystore with
`-delete -alias opensearch-custom-company-root`.
Each trusted alias holds one certificate. Usually only the root CA needs importing;
the server supplies its intermediates. If you deliberately trust several CAs,
import each certificate separately, for example as `opensearch-custom-yolo-0`
and `opensearch-custom-yolo-1`. Passing a whole PEM bundle to one new alias does
not import every CA. The command keeps native keytool behavior and does not split
bundles or add the alias prefix automatically.

Custom entries and their deletions survive refresh and revert. Keep this managed
store's password as `changeit`; separately configured truststores remain your
responsibility. Finish custom CA edits before starting a refresh or revert.
Reverting to a snap predating this fix cannot update the shared
store automatically because its startup script has no update step.

### Plugin removal and rollback

Plugins bundled with this snap must remain installed. `opensearch.plugin remove`
rejects their removal, including with `--purge`, without changing their files or
configuration. Where a plugin supports disabling features, use its upstream
settings or API. To choose which plugins are installed, use the
`opensearch-chiseled` snap instead.

Plugin configuration normally stays shared across revisions. If you change a
plugin's settings from A to B and revert, the plugin continues to use B.

`sudo snap run opensearch.plugin remove <plugin> --purge` removes the current
plugin and its live configuration. If you then revert to a retained revision,
the snap restores that revision's saved configuration A, provided the plugin
still matches and its configuration directory is missing. Existing directories
are never overwritten or merged, including after a plugin reinstall.

Missing plugin configuration is recovered at startup regardless of whether a
purge or manual deletion removed it. Native removal updates the active revision's
saved copy, so restarting that revision does not undo its own purge.

Each revision saves its plugin configuration before refresh, when the service
stops, and after startup recovery. These private copies stay in that revision's
data and are removed with the revision. Recovery requires a revision that already
supports this mechanism; it cannot reconstruct configuration from older snaps
that never saved it. The main `opensearch.yml`, keystore, and certificates remain
shared and are not restored by this mechanism.

### Heap dumps

On a Java heap exhaustion, the default JVM settings write a dump to
`/var/snap/opensearch/common/var/log/opensearch/java_heapdump.hprof`.
This requires enough free disk space. The JVM keeps the first dump and refuses
to overwrite it; move or remove it after investigation to allow another dump.
Heap dumps can contain credentials and document contents: keep them private.
Refresh preserves a custom `-XX:HeapDumpPath` setting in `jvm.options`.

### Testing the OpenSearch setup:
You can either consume the REST API yourself or see if the below commands succeed, and you see that the tests `"PASSED"` successfully: 
```
# The admin password generated on install (root only):
ADMIN_PASSWORD=$(sudo sed -n 's/^admin: "\(.*\)"$/\1/p' /var/snap/opensearch/common/init_users_pass.yaml)

# Check if cluster is healthy (green):
sudo snap run opensearch.test-cluster-health-green --admin-auth-password "$ADMIN_PASSWORD"
> ....
> PASSED


# Check if node is up:
sudo snap run opensearch.test-node-up --node-name "opensearch-$(hostname)" --admin-auth-password "$ADMIN_PASSWORD"
> ....
> PASSED


# Check if the security index is well initialised:
sudo snap run opensearch.test-security-index-created --admin-auth-password "$ADMIN_PASSWORD"
> ....
> PASSED
```

or:
```
sudo curl --cacert /var/snap/opensearch/common/etc/opensearch/certificates/root-ca.pem \
    -u "admin:$ADMIN_PASSWORD" https://localhost:9200/_cluster/health?pretty
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
