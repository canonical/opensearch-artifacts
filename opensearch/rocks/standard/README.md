# OpenSearch Rock (OCI Image)

[OpenSearch](https://opensearch.org/) is an open-source search and analytics suite. Developers build solutions for search, data observability, data ingestion and more using OpenSearch. OpenSearch is offered under the Apache Software Licence, version 2.0.

The [OpenSearch rock](https://github.com/canonical/opensearch-artifacts) is an Open Container Initiative (OCI) image derived from the [opensearch Snap](https://snapcraft.io/opensearch). The tool used to create this rock is called [Rockcraft](https://canonical-rockcraft.readthedocs-hosted.com/en/latest/index.html).

This repository contains the packaging metadata for creating the OpenSearch rock. This rock image is based on the [opensearch Snap](https://github.com/canonical/opensearch-artifacts/tree/add-standard-3-edge-rock/opensearch/snaps/standard).

For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Version

The OpenSearch rock release aligns with the [OpenSearch upstream major version](https://opensearch.org/docs/latest/version-history/) naming. OpenSearch releases major versions such as 1.0, 2.0, and so on.

## Supported Platforms

The rock is built for `amd64` and `arm64` architectures. Use `rockcraft pack` on a host matching the target architecture, or pass `--platform` to cross-build (e.g. `rockcraft pack --platform arm64`).

## Rock Usage

### Building the Rock

The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different. To avoid any issue with other operating systems you can simply build the image with [multipass](https://multipass.run/):

sudo snap install multipass
multipass launch 22.04 -n rock-dev
multipass shell rock-dev

#### Clone Repository

git clone https://github.com/canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/rocks/standard

#### Installing Prerequisites

sudo snap install rockcraft --classic --edge
sudo snap install docker
sudo snap install lxd

#### Configuring Prerequisites

sudo usermod -aG docker $USER 
sudo lxd init --auto

**NOTE:** You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)

#### Packing and Running the Rock

rockcraft pack

version="$(cat rockcraft.yaml | yq .version)"
arch="$(dpkg --print-architecture)"

rockcraft.skopeo --insecure-policy \
  copy \
  oci-archive:opensearch_"${version}"_"${arch}".rock \
  docker-daemon:opensearch:"${version}"

docker run \
  -d --rm -it \
  -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>" \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch:"${version}"

curl -k -u admin:"<strong-password>" https://localhost:9200

Like with the upstream image, `OPENSEARCH_INITIAL_ADMIN_PASSWORD` is required
unless the security plugin is disabled (see [Security](#security)).

Like with the upstream image, a node needs discovery settings to start: here
`INITIAL_CM_NODES`, the node bootstrapping the cluster. For a single node, you
can pass `-e discovery.type=single-node` instead. Without either, the node stops
on a failed bootstrap check: "the default discovery settings are unsuitable for
production use".

### Configuration

The rock's `/usr/share/opensearch/config/opensearch.yml` sets:

```yaml
cluster.name: opensearch-cluster
network.host: 0.0.0.0
```

`0.0.0.0` includes `localhost`, which the security tools connect to. Other
settings take the OpenSearch defaults, like with the upstream image. For
example, the node is named after the container hostname and has the default
roles.

These variables, when set, override a setting. Lists are comma separated:

| Variable | Setting |
|---|---|
| `CLUSTER_NAME` | `cluster.name` |
| `NODE_NAME` | `node.name` |
| `NODE_ROLES` | `node.roles` |
| `INITIAL_CM_NODES` | `cluster.initial_cluster_manager_nodes`, on cluster manager eligible nodes only |
| `NETWORK_HOST` | `network.host` |
| `SEED_HOSTS` | `discovery.seed_hosts` |

Like with the upstream image, any setting can also be passed as a variable
named after it, e.g. `-e indices.query.bool.max_clause_count=2048`, which takes
precedence over the variables above. The overrides are passed to OpenSearch as
`-E` options, which take precedence over `opensearch.yml`: the file itself is
never modified.

You can mount your own `opensearch.yml`, which replaces the rock's, read-only
if you want:

```bash
docker run ... \
  -v ./opensearch.yml:/usr/share/opensearch/config/opensearch.yml:ro \
  opensearch:"${version}"
```

Unless the file already configures the security plugin, the demo
configuration (see [Security](#security)) appends its settings to it, which
requires the file to be writable by the `_daemon_` user (584792). With your own
security configuration, set `DISABLE_INSTALL_DEMO_CONFIG=true`. The demo
configuration is installed in `/usr/share/opensearch/config`: it can not be used
with another `OPENSEARCH_PATH_CONF`, the rock stops with an error.

### Logs

Like with the upstream image, the output of OpenSearch, including why it failed
to start, is in the container logs: `docker logs <container>`. When OpenSearch
stops, so does the container.

Like with the upstream image, a few startup errors, such as a data directory
that OpenSearch can not write, leave its JVM running after the error, kept
alive by the threads of the Performance Analyzer plugin: the container keeps
running, without serving requests. A [health check](#health-checks) reports it
as unhealthy.

### Health checks

The rock has no built-in health check. This one checks that the node answers
HTTPS, whatever the answer, so it needs no credentials. `-k` skips the
certificate verification of this request to `localhost`, inside the container:

```bash
docker run ... \
  --health-cmd 'curl -sk -o /dev/null https://localhost:9200' \
  --health-interval 10s --health-timeout 5s --health-retries 3 \
  --health-start-period 2m \
  opensearch:"${version}"

docker inspect -f '{{.State.Health.Status}}' <container>
```

Docker only reports an unhealthy container, it does not restart it. An
orchestrator can run the same command as a liveness probe.

Before sending requests, wait for the cluster to be ready, as a user allowed to
read the cluster health. `-f` makes `curl` fail when the status is not reached
within the timeout:

```bash
curl -f --cacert root-ca.pem -u admin \
  'https://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=60s'
```

### Security

Like the upstream `opensearchproject/opensearch` image, the rock starts with the
security plugin enabled and TLS on both the transport and REST layers. On first
start it runs the security plugin's `install_demo_configuration.sh`, which
installs the demo certificates and sets the password of the `admin` user.

| Variable | Description |
|---|---|
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | Password of the `admin` user, required. It must be at least 8 characters long, contain an uppercase letter, a lowercase letter, a digit and a special character, and be rated strong by [zxcvbn](https://lowe.github.io/tryzxcvbn). |
| `OPENSEARCH_INITIAL_<USER>_PASSWORD` | Password of the other users of the demo configuration: `ANOMALYADMIN`, `KIBANARO`, `KIBANASERVER`, `LOGSTASH`, `READALL`, `SNAPSHOTRESTORE`, e.g. `OPENSEARCH_INITIAL_KIBANASERVER_PASSWORD`. When not set, the user keeps its demo password, the same as its name, like with the upstream image. |
| `DISABLE_INSTALL_DEMO_CONFIG` | Set to `true` to skip the demo configuration, e.g. when you mount your own certificates and security configuration. |
| `DISABLE_SECURITY_PLUGIN` | Set to `true` to start OpenSearch with the security plugin disabled (plain HTTP, no authentication). The demo configuration is then skipped and no password is needed. |

The demo passwords are public. Set the password of every demo user you keep,
and remove or disable the others, with the security REST API or
`securityadmin.sh`. The given passwords are stored as bcrypt hashes in
`internal_users.yml`, then in the security index, never in plain text.

Like with the upstream image, a rejected admin password is printed in the logs
by the demo configuration.

Like with the upstream image, the passwords are set by the first start only,
which creates the security index in the data directory. A container that
reuses the data directory, e.g. with `-v opensearch:/usr/share/opensearch/data`,
keeps the passwords of the first one: the `OPENSEARCH_INITIAL_<USER>_PASSWORD`
variables no longer change them. Its demo configuration still requires an
`OPENSEARCH_INITIAL_ADMIN_PASSWORD`, which does not change the admin password
either: pass the same one to avoid confusion. To change a password later, use
the [security REST API](https://docs.opensearch.org/latest/security/access-control/api/)
or `securityadmin.sh`, after a backup of the security configuration with
`securityadmin.sh -backup`.

Like with the upstream image, the API refuses to change the reserved users,
`admin` and `kibanaserver`, unless the request is authenticated with the admin
certificate, `kirk.pem` in the demo configuration. The new password is read
from the standard input, to keep it out of the process list:

```bash
docker exec -i -w /usr/share/opensearch/config <container> \
  curl -s --cacert root-ca.pem --cert kirk.pem --key kirk-key.pem \
  -X PATCH https://localhost:9200/_plugins/_security/api/internalusers/admin \
  -H 'Content-Type: application/json' -d @- <<'EOF'
[{"op": "add", "path": "/password", "value": "<new-password>"}]
EOF
```

The `OPENSEARCH_INITIAL_*_PASSWORD` variables are removed from the environment
of OpenSearch, but Docker keeps them in the container configuration, shown by
`docker inspect`.

Pass TLS secrets, such as the password of a private key, as
[secure settings](https://docs.opensearch.org/latest/security/configuration/opensearch-keystore/)
in the keystore rather than as variables: unlike the keystore, the variables
are shown by `docker inspect`.

The users are stored in the security index of the cluster, created by the first
node: in a multi-node cluster, the passwords of that node apply to all of them.
Passing the same passwords to every node, as in the example below, avoids
looking them up.

The demo certificates are the same on every node, which lets a multi-node
cluster form out of the box, but their private keys are public: do not use them
in production.

### Running the OpenSearch tools

The OpenSearch tools (`opensearch-keystore`, `opensearch-plugin`, ...) are on
the `PATH`, and the security plugin tools (`securityadmin.sh`, `hash.sh`, ...)
are in `/usr/share/opensearch/plugins/opensearch-security/tools`.

OpenSearch and `docker exec` both run as the `_daemon_` user (584792:584792),
so the files the tools write, such as the keystore, stay readable by OpenSearch:

```bash
echo "<value>" | docker exec -i <container> \
  opensearch-keystore add --stdin <setting>
docker exec <container> opensearch-keystore list
```

This keystore is in the container: it is lost when the container is replaced.
To keep it, mount a keystore file, as in
[Production deployment](#production-deployment).

### Production deployment

In production, replace the demo configuration with your own certificates and
security configuration, and set `DISABLE_INSTALL_DEMO_CONFIG=true`. The example
below runs a single node, `node1`. In a cluster, each node has its own
certificate, listed in `plugins.security.nodes_dn`, and the discovery settings
of [Configuration](#configuration).

Create a certificate authority, a certificate for the node, valid for the names
the clients connect to, and an admin certificate for the security tools. The
key of the certificate authority stays out of the containers:

```bash
mkdir -m 700 ca admin
mkdir certs

openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 730 \
  -subj "/CN=opensearch-root-ca" \
  -keyout ca/root-ca-key.pem -out certs/root-ca.pem

openssl req -newkey rsa:3072 -nodes -subj "/CN=node1" \
  -keyout certs/node1-key.pem -out node1.csr
openssl x509 -req -sha256 -days 365 -in node1.csr \
  -CA certs/root-ca.pem -CAkey ca/root-ca-key.pem \
  -CAserial ca/root-ca.srl -CAcreateserial \
  -extfile <(printf "subjectAltName=DNS:node1,DNS:localhost,IP:127.0.0.1") \
  -out certs/node1.pem

openssl req -newkey rsa:3072 -nodes -subj "/CN=admin" \
  -keyout admin/admin-key.pem -out admin.csr
openssl x509 -req -sha256 -days 365 -in admin.csr \
  -CA certs/root-ca.pem -CAkey ca/root-ca-key.pem \
  -CAserial ca/root-ca.srl -CAcreateserial \
  -out admin/admin.pem
cp certs/root-ca.pem admin/

rm node1.csr admin.csr
```

Copy the default security configuration out of the rock:

```bash
docker create --name opensearch-files opensearch:"${version}"
docker cp opensearch-files:/usr/share/opensearch/config/opensearch-security .
docker rm opensearch-files
```

Hash the admin password, which the tool asks for:

```bash
docker run --rm -it \
  --entrypoint /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh \
  opensearch:"${version}"
```

Replace `opensearch-security/internal_users.yml` with the users you need only,
here `admin` with that hash:

```yaml
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "<hash>"
  reserved: true
  backend_roles:
  - "admin"
  description: "Admin user"
```

Write the `opensearch.yml` of the node. With
`plugins.security.allow_default_init_securityindex`, the first start creates the
security index from `opensearch-security`, without `securityadmin.sh`:

```yaml
cluster.name: opensearch-cluster
network.host: 0.0.0.0

plugins.security.ssl.transport.pemcert_filepath: certs/node1.pem
plugins.security.ssl.transport.pemkey_filepath: certs/node1-key.pem
plugins.security.ssl.transport.pemtrustedcas_filepath: certs/root-ca.pem
plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemcert_filepath: certs/node1.pem
plugins.security.ssl.http.pemkey_filepath: certs/node1-key.pem
plugins.security.ssl.http.pemtrustedcas_filepath: certs/root-ca.pem
plugins.security.authcz.admin_dn: ["CN=admin"]
plugins.security.nodes_dn: ["CN=node1"]
plugins.security.allow_default_init_securityindex: true
plugins.security.restapi.roles_enabled: ["all_access", "security_rest_api_access"]
```

Give the files to the `_daemon_` user (584792), the private keys and the
security configuration readable by it only:

```bash
sudo chown -R 584792:584792 opensearch.yml certs opensearch-security admin
sudo chmod 600 opensearch.yml certs/node1-key.pem admin/admin-key.pem
sudo find opensearch-security -type f -exec chmod 600 {} +
sudo chmod 700 opensearch-security admin
```

Start the node, with its configuration mounted read-only, and check it with
the certificate authority:

```bash
docker run -d --name node1 -p 9200:9200 \
  -e DISABLE_INSTALL_DEMO_CONFIG=true \
  -e discovery.type=single-node \
  -v ./opensearch.yml:/usr/share/opensearch/config/opensearch.yml:ro \
  -v ./certs:/usr/share/opensearch/config/certs:ro \
  -v ./opensearch-security:/usr/share/opensearch/config/opensearch-security:ro \
  -v opensearch-data:/usr/share/opensearch/data \
  opensearch:"${version}"

curl --cacert certs/root-ca.pem -u admin https://localhost:9200
```

Once the security index exists, changing the files of `opensearch-security`
no longer changes the users: use the security REST API or `securityadmin.sh`.
Run the tools needing the admin certificate in a one-off container sharing the
network of the node, so the admin key is never mounted in the node. For
example, a backup of the security configuration:

```bash
mkdir -m 700 backup
sudo chown 584792:584792 backup
docker run --rm --network container:node1 \
  -v ./admin:/admin:ro -v ./backup:/backup \
  --entrypoint /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
  opensearch:"${version}" \
  -backup /backup -icl \
  -cacert /admin/root-ca.pem -cert /admin/admin.pem -key /admin/admin-key.pem
```

Or a new password for the reserved `admin` user:

```bash
docker run --rm -i --network container:node1 -v ./admin:/admin:ro \
  --entrypoint curl opensearch:"${version}" -s \
  --cacert /admin/root-ca.pem --cert /admin/admin.pem --key /admin/admin-key.pem \
  -X PATCH https://localhost:9200/_plugins/_security/api/internalusers/admin \
  -H 'Content-Type: application/json' -d @- <<'EOF'
[{"op": "add", "path": "/password", "value": "<new-password>"}]
EOF
```

#### Encrypted private key

To keep the node key encrypted, give its password to OpenSearch as secure
settings, in a keystore file created by a one-off container. Mounted
read-only, the keystore is kept when the container is replaced. Encrypt the
key, `openssl` asks for the password:

```bash
sudo openssl pkcs8 -topk8 -v2 aes-256-cbc \
  -in certs/node1-key.pem -out certs/node1-key-enc.pem
sudo chown 584792:584792 certs/node1-key-enc.pem
sudo chmod 600 certs/node1-key-enc.pem
sudo rm certs/node1-key.pem
```

Point `pemkey_filepath`, for both `transport` and `http`, to
`certs/node1-key-enc.pem` in `opensearch.yml`, then create the keystore, the
container asks for the password:

```bash
mkdir -m 700 keystore
sudo chown 584792:584792 keystore
docker run --rm -it -v ./keystore:/keystore \
  --entrypoint bash opensearch:"${version}" -c '
    set -eu
    read -rsp "Key password: " password
    echo
    opensearch-keystore create
    for layer in transport http; do
      printf "%s" "${password}" | opensearch-keystore add --stdin \
        "plugins.security.ssl.${layer}.pemkey_password_secure"
    done
    cp /usr/share/opensearch/config/opensearch.keystore /keystore/'
```

Mount it in the node:

```bash
docker run ... \
  -v ./keystore/opensearch.keystore:/usr/share/opensearch/config/opensearch.keystore:ro \
  opensearch:"${version}"
```

### Moving from the upstream image

The upstream image runs OpenSearch as the user 1000, the rock as `_daemon_`
(584792). Before using the data of an upstream container with the rock, stop
it, then give its data to `_daemon_`:

```bash
docker run --rm --user 0 \
  -v opensearch-data:/usr/share/opensearch/data \
  --entrypoint chown opensearch:"${version}" \
  -R 584792:584792 /usr/share/opensearch/data
```

For a host directory: `sudo chown -R 584792:584792 <directory>`. Otherwise, the
node fails with an `AccessDeniedException` on the data directory, and keeps
running (see [Logs](#logs)). The indices and the security index, so the users
and their passwords, are kept. To go back to the upstream image, give the data
back to the user 1000.

### Performance Analyzer

The Performance Analyzer plugin is included, but not its agent, which serves
the metrics on port 9600. Since OpenSearch 3.0, the plugin no longer bundles
the agent's libraries (`performance-analyzer-rca`): in the upstream image, the
agent fails to start, and port 9600 is closed, like in the rock.

### Heap dumps

On a Java heap exhaustion, OpenSearch writes a heap dump to
`/usr/share/opensearch/data/java_heapdump.hprof`, next to the indices: mount a
volume on the data directory to keep it when the container is recreated. The
JVM keeps the first dump and refuses to overwrite it, so restarts on repeated
out of memory errors cannot fill the disk: copy it out and remove it after
investigation to allow another one. A dump is as large as the heap and can
contain credentials and document contents: keep it private.

```bash
docker cp <container>:/usr/share/opensearch/data/java_heapdump.hprof .
docker exec <container> rm /usr/share/opensearch/data/java_heapdump.hprof
```

The location does not follow `path.data`. To keep the dumps in another
directory, override it in `OPENSEARCH_JAVA_OPTS`. The directory needs room for
one dump, and must be writable by the `_daemon_` user only:

```bash
mkdir -m 700 diagnostics
sudo chown 584792:584792 diagnostics
docker run ... \
  -v ./diagnostics:/diagnostics \
  -e OPENSEARCH_JAVA_OPTS="-XX:HeapDumpPath=/diagnostics/java_heapdump.hprof" \
  opensearch:"${version}"
```

### Testing a multi nodes deployment:

```
# create first cm_node container
container_0_id=$(docker run \
  -d --rm -it \
  -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>" \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch:"${version}")
container_0_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_0_id}")

# wait a bit for it to fully initialize
sleep 15s

# create data/voting_only node container
container_1_id=$(docker run \
    -d --rm -it \
    -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>" \
    -e NODE_NAME=data1 \
    -e SEED_HOSTS="${container_0_ip}" \
    -e NODE_ROLES=data,voting_only \
    -p 9201:9200 \
    --name data1 \
    opensearch:"${version}")
container_1_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_1_id}")

# wait a bit for it to fully initialize
sleep 15s

# create 2nd cm_node container
container_2_id=$(docker run \
    -d --rm -it \
    -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>" \
    -e NODE_NAME=cm1 \
    -e SEED_HOSTS="${container_0_ip},${container_1_ip}" \
    -e INITIAL_CM_NODES="cm0,cm1" \
    -p 9202:9200 \
    --name cm1 \
    opensearch:"${version}")

# wait a bit for it to fully initialize
sleep 15s
```

You now can query the nodes:

```
curl -k -u admin:"<strong-password>" -X GET https://127.0.0.1:9200/_nodes/
```

And expect to see 3 nodes.

**NOTE:** This deployment IS NOT suitable for production AS IS, as it secures OpenSearch with the publicly known demo certificates. See [Production deployment](#production-deployment), or use it as part of the Juju OpenSearch K8s charm once ready.

## License

The OpenSearch rock is free software, distributed under the Apache Software License, version 2.0. See [LICENSE](https://github.com/canonical/opensearch-artifacts/blob/main/LICENSE) for more information.

## Security, Bugs and feature request

If you find a bug in this rock or want to request a specific feature, here are the useful links:

- Raise the issue or feature request in the [Canonical GitHub repository](https://github.com/canonical/opensearch-artifacts/issues).
- Meet the community and chat with us if there are issues and feature requests in our [Mattermost Channel](https://chat.charmhub.io/charmhub/channels/data-platform).

## Contributing

Please see the [Juju SDK docs](https://juju.is/docs/sdk) for guidelines on enhancements to this charm following best practice guidelines, and [CONTRIBUTING.md](https://github.com/canonical/mongodb-operator/blob/main/CONTRIBUTING.md) for developer guidance.

## Trademark notice

OpenSearch is a registered trademark of Amazon Web Services. Other trademarks are property of their respective owners. OpenSearch is not sponsored, endorsed, or affiliated with Amazon Web Services.

## License

The OpenSearch rock, OpenSearch Snap, and OpenSearch Operator are free software, distributed under the [Apache Software License, version 2.0](https://github.com/canonical/opensearch-artifacts/blob/main/LICENSE). They install and operate OpenSearch, which is also licensed under the [Apache Software License, version 2.0](https://github.com/canonical/opensearch-rock/blob/main/licenses/LICENSE-opensearch).
