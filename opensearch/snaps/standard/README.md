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

#### Replacing the certificates:
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

Then restart the daemon, and re-initialize the security index if the admin certificate changed:
```
sudo snap restart opensearch.daemon
sudo snap run opensearch.security-init    # --tls-priv-key-admin-pass <pass> for an encrypted admin key
```

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
