# OpenSearch Dashboards Rock (OCI Image)

[OpenSearch Dashboards](https://opensearch.org/docs/latest/dashboards/) is a community-driven, Apache 2.0-licensed user interface that lets you visualize your OpenSearch data, and run and scale your OpenSearch clusters.

The [OpenSearch Dashboards rock](https://github.com/canonical/opensearch-artifacts) is an Open Container Initiative (OCI) image derived from the [opensearch-dashboards Snap](https://snapcraft.io/opensearch-dashboards). The tool used to create this rock is called [Rockcraft](https://canonical-rockcraft.readthedocs-hosted.com/en/latest/index.html).

This repository contains the packaging metadata for creating the OpenSearch Dashboards rock. For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Supported Platforms

The rock is built for `amd64` and `arm64` architectures. Use `rockcraft pack` on a host matching the target architecture, or pass `--platform` to cross-build (e.g. `rockcraft pack --platform arm64`).

## Rock Usage

### Building the Rock

The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different.

#### Clone Repository

```bash
git clone https://github.com/canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch-dashboards/rocks/standard
```

#### Installing Prerequisites

```bash
sudo snap install rockcraft --classic --edge
sudo snap install docker
sudo snap install lxd
```

#### Configuring Prerequisites

```bash
sudo usermod -aG docker $USER
sudo lxd init --auto
```

**NOTE:** You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)

#### Packing and Running the Rock

```bash
rockcraft pack

version="$(yq -r .version rockcraft.yaml)"
arch="$(dpkg --print-architecture)"

rockcraft.skopeo --insecure-policy \
  copy \
  oci-archive:opensearch-dashboards_"${version}"_"${arch}".rock \
  docker-daemon:opensearch-dashboards:"${version}"

docker run \
  -d -it \
  -e OPENSEARCH_HOSTS='["https://<opensearch-host>:9200"]' \
  -p 5601:5601 \
  --name osd \
  opensearch-dashboards:"${version}"
```

OpenSearch Dashboards is then served on http://localhost:5601.

Like with the upstream image, it connects to OpenSearch over HTTPS with the
`kibanaserver` user of the demo security configuration, without verifying the
OpenSearch certificates (see [Security](#security)).

### Example alongside the OpenSearch rock

The [OpenSearch rock](../../../opensearch/rocks/standard/README.md) starts, like
the upstream image, with the demo security configuration, which the default
configuration of this rock connects to. The containers reach each other by
name on the same network:

```bash
docker network create opensearch-net

docker run \
  -d -it \
  --network opensearch-net \
  -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>" \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch:"${version}"

docker run \
  -d -it \
  --network opensearch-net \
  -e OPENSEARCH_HOSTS='["https://cm0:9200"]' \
  -p 5601:5601 \
  --name osd \
  opensearch-dashboards:"${version}"
```

Log in on http://localhost:5601 as `admin`, with the password given to
OpenSearch.

**NOTE:** This deployment IS NOT suitable for production AS IS: it uses the
publicly known demo password of `kibanaserver` and does not verify the
OpenSearch certificates. See [Production deployment](#production-deployment).

### Configuration

Like with the upstream image, OpenSearch Dashboards lives in
`/usr/share/opensearch-dashboards`, with its configuration in `config`, its data
in `data` and its plugins in `plugins`.

The rock's `/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml`
is the one of the OpenSearch Dashboards tarball, served on all the interfaces
like with the upstream image:

```yaml
opensearch.hosts: [https://localhost:9200]
opensearch.ssl.verificationMode: none
opensearch.username: kibanaserver
opensearch.password: kibanaserver
opensearch.requestHeadersWhitelist: [authorization, securitytenant]

opensearch_security.multitenancy.enabled: true
opensearch_security.multitenancy.tenants.preferred: [Private, Global]
opensearch_security.readonly_mode.roles: [kibana_read_only]
opensearch_security.cookie.secure: false
server.host: '0.0.0.0'
```

The most used settings can be passed as a variable, named as in the upstream
image:

| Variable | Setting |
|---|---|
| `OPENSEARCH_HOSTS` | `opensearch.hosts` |
| `OPENSEARCH_USERNAME` | `opensearch.username` |
| `OPENSEARCH_PASSWORD` | `opensearch.password` |
| `OPENSEARCH_SSL_VERIFICATIONMODE` | `opensearch.ssl.verificationMode` |
| `OPENSEARCH_SSL_CERTIFICATE` | `opensearch.ssl.certificate` |
| `OPENSEARCH_SSL_CERTIFICATEAUTHORITIES` | `opensearch.ssl.certificateAuthorities` |
| `OPENSEARCH_SSL_KEY` | `opensearch.ssl.key` |
| `OPENSEARCH_SSL_KEYPASSPHRASE` | `opensearch.ssl.keyPassphrase` |
| `OPENSEARCH_SSL_KEYSTORE_PATH` | `opensearch.ssl.keystore.path` |
| `OPENSEARCH_SSL_KEYSTORE_PASSWORD` | `opensearch.ssl.keystore.password` |
| `OPENSEARCH_SSL_TRUSTSTORE_PATH` | `opensearch.ssl.truststore.path` |
| `OPENSEARCH_SSL_TRUSTSTORE_PASSWORD` | `opensearch.ssl.truststore.password` |
| `SERVER_HOST` | `server.host` |
| `SERVER_PORT` | `server.port` |
| `SERVER_SSL_ENABLED` | `server.ssl.enabled` |
| `SERVER_SSL_CERTIFICATE` | `server.ssl.certificate` |
| `SERVER_SSL_KEY` | `server.ssl.key` |

Unlike the upstream image, the rock reads no other setting from a variable:
the other variables of the upstream image, such as `SERVER_NAME`, are ignored.

The variables are passed to OpenSearch Dashboards as `--<setting>=<value>`
options, which take precedence over `opensearch_dashboards.yml`: the file itself
is never modified. OpenSearch Dashboards reads a value that is valid JSON as
JSON, so a list is written as a JSON list, and a single host as is:

```bash
docker run ... \
  -e OPENSEARCH_HOSTS='["https://node1:9200","https://node2:9200"]' \
  opensearch-dashboards:"${version}"

docker run ... \
  -e OPENSEARCH_HOSTS=https://node1:9200 \
  opensearch-dashboards:"${version}"
```

For any other setting, mount your own `opensearch_dashboards.yml`, which
replaces the rock's, read-only if you want:

```bash
docker run ... \
  -v ./opensearch_dashboards.yml:/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml:ro \
  opensearch-dashboards:"${version}"
```

The file must be readable by the `_daemon_` user (584792). OpenSearch Dashboards
refuses to start with an unknown setting (`Unknown configuration key(s)`) or a
value of the wrong type: the container stops, and its [logs](#logs) say why.

The options of Node.js, such as the size of its heap, are read from
`/usr/share/opensearch-dashboards/config/node.options`, which can be mounted the
same way.

### Logs

Like with the upstream image, the output of OpenSearch Dashboards, including why
it failed to start, is in the container logs: `docker logs <container>`. When
OpenSearch Dashboards stops, so does the container.

To write the logs to a file instead, set `logging.dest` in
`opensearch_dashboards.yml` (see [Configuration](#configuration)) to a path
writable by the `_daemon_` user (584792), e.g. in a mounted directory.

OpenSearch Dashboards keeps running when it can not reach OpenSearch or log in
to it at startup: it answers `OpenSearch Dashboards server is not ready yet`
with the status 503, and its logs say why, until the connection succeeds. A
[health check](#health-checks) reports it as unhealthy.

### Health checks

The rock has no built-in health check. This one checks that OpenSearch
Dashboards is ready, with or without its security plugin, so it needs no
credentials: `/api/status` answers 503 until OpenSearch Dashboards is connected
to OpenSearch, then 200, or 401 when it asks for credentials.

```bash
docker run ... \
  --health-cmd "curl -s -o /dev/null -w '%{http_code}' http://localhost:5601/api/status | grep -q '^[24]'" \
  --health-interval 10s --health-timeout 5s --health-retries 3 \
  --health-start-period 1m \
  opensearch-dashboards:"${version}"

docker inspect -f '{{.State.Health.Status}}' <container>
```

When OpenSearch Dashboards is served over HTTPS, as in
[Production deployment](#production-deployment), check
`https://localhost:5601/api/status` instead, with the `-k` option of `curl`.

The check tells when OpenSearch Dashboards has started. Once ready, it keeps
answering 200 or 401 when OpenSearch becomes unreachable: its logs report it,
and it reconnects by itself when OpenSearch is back.

Docker only reports an unhealthy container, it does not restart it. An
orchestrator can run the same command as a readiness probe.

### Security

Like the upstream `opensearchproject/opensearch-dashboards` image, the rock
starts with the security plugin enabled, and connects to OpenSearch as the
`kibanaserver` user with its demo password, `kibanaserver`.

| Variable | Description |
|---|---|
| `OPENSEARCH_USERNAME` | User OpenSearch Dashboards connects to OpenSearch with, `kibanaserver` by default. |
| `OPENSEARCH_PASSWORD` | Password of that user. With the OpenSearch rock, the one given in `OPENSEARCH_INITIAL_KIBANASERVER_PASSWORD`. |
| `OPENSEARCH_SSL_CERTIFICATEAUTHORITIES` | Path, in the container, of the PEM file of the CA that signed the OpenSearch certificates. |
| `OPENSEARCH_SSL_VERIFICATIONMODE` | `none` by default. `certificate` verifies that the OpenSearch certificates are signed by the CA, `full` also that they are valid for the hosts of `OPENSEARCH_HOSTS`. |
| `DISABLE_SECURITY_DASHBOARDS_PLUGIN` | Set to `true` to start OpenSearch Dashboards with its security plugin disabled, for an OpenSearch without the security plugin. |

The demo password is public. Set the password of `kibanaserver` in OpenSearch,
and give it to OpenSearch Dashboards. Docker keeps the variables in the
container configuration, shown by `docker inspect`, and the options of
OpenSearch Dashboards are in its command line: prefer the
[keystore](#running-the-opensearch-dashboards-tools) for the password, which
takes precedence over both `OPENSEARCH_PASSWORD` and
`opensearch_dashboards.yml`.

The demo certificates of OpenSearch are valid for `localhost` and
`node-0.example.com` only, so the `full` mode refuses them for any other host:
use `certificate` with them, and `full` with your own certificates.

With `DISABLE_SECURITY_DASHBOARDS_PLUGIN=true`, OpenSearch Dashboards asks for
no credentials. The upstream image removes the plugin and rewrites
`opensearch_dashboards.yml`, replacing `https` by `http`. The rock disables the
plugin with the `--opensearch_security.enabled=false` option instead, and leaves
the plugin and the file as they are: set the `http` hosts yourself.

```bash
docker run ... \
  -e DISABLE_SECURITY_DASHBOARDS_PLUGIN=true \
  -e OPENSEARCH_HOSTS=http://<opensearch-host>:9200 \
  opensearch-dashboards:"${version}"
```

### Running the OpenSearch Dashboards tools

The OpenSearch Dashboards tools, `opensearch-dashboards-keystore` and
`opensearch-dashboards-plugin`, are on the `PATH`.

OpenSearch Dashboards and `docker exec` both run as the `_daemon_` user
(584792:584792), so the files the tools write, such as the keystore, stay
readable by OpenSearch Dashboards. Restart the container to apply the changes:

```bash
docker exec <container> opensearch-dashboards-keystore create
echo "<password>" | docker exec -i <container> \
  opensearch-dashboards-keystore add --stdin opensearch.password
docker exec <container> opensearch-dashboards-keystore list

docker exec <container> opensearch-dashboards-plugin list
docker exec <container> opensearch-dashboards-plugin install <url>
docker exec <container> opensearch-dashboards-plugin remove <plugin>

docker restart <container>
```

Like with the upstream image, a plugin should be built for the same version of
OpenSearch Dashboards.

The keystore and the plugins are in the container: they are lost when the
container is replaced. To keep them, mount a keystore file, as in
[Production deployment](#production-deployment), and install the plugins in an
image built from the rock:

```dockerfile
FROM opensearch-dashboards:<version>
RUN opensearch-dashboards-plugin install <url>
```

### Production deployment

In production, replace the demo password of `kibanaserver`, verify the
OpenSearch certificates, and serve OpenSearch Dashboards over HTTPS. The
example below connects to an OpenSearch cluster whose certificates are signed
by the CA in `certs/root-ca.pem`, with `certs/osd.pem` and `certs/osd-key.pem`
the certificate, signed by the same CA, and the key of OpenSearch Dashboards.

OpenSearch must know the `kibanaserver` user. With the production deployment
of the OpenSearch rock, add it to its `internal_users.yml`, next to `admin`,
with the hash of the password you choose; the default `roles_mapping.yml` gives
it the `kibana_server` role:

```yaml
kibanaserver:
  hash: "<hash>"
  reserved: true
  description: "OpenSearch Dashboards user"
```

Give the files to the `_daemon_` user (584792), the private key readable by it
only:

```bash
sudo chown -R 584792:584792 certs
sudo chmod 600 certs/osd-key.pem
```

Store the password of `kibanaserver` in a keystore file created by a one-off
container, which asks for it:

```bash
mkdir -m 700 keystore
sudo chown 584792:584792 keystore
docker run --rm -it -v ./keystore:/keystore \
  --entrypoint bash opensearch-dashboards:"${version}" -c '
    set -eu
    read -rsp "kibanaserver password: " password
    echo
    opensearch-dashboards-keystore create
    printf "%s" "${password}" | opensearch-dashboards-keystore add --stdin \
      opensearch.password
    cp /usr/share/opensearch-dashboards/config/opensearch_dashboards.keystore \
      /keystore/'
```

Start OpenSearch Dashboards with the keystore and the certificates mounted
read-only:

```bash
conf=/usr/share/opensearch-dashboards/config
docker run -d --name osd -p 5601:5601 \
  -e OPENSEARCH_HOSTS='["https://node1:9200"]' \
  -e OPENSEARCH_SSL_CERTIFICATEAUTHORITIES="${conf}/certs/root-ca.pem" \
  -e OPENSEARCH_SSL_VERIFICATIONMODE=full \
  -e SERVER_SSL_ENABLED=true \
  -e SERVER_SSL_CERTIFICATE="${conf}/certs/osd.pem" \
  -e SERVER_SSL_KEY="${conf}/certs/osd-key.pem" \
  -v ./certs:"${conf}/certs":ro \
  -v ./keystore/opensearch_dashboards.keystore:"${conf}/opensearch_dashboards.keystore":ro \
  opensearch-dashboards:"${version}"

curl --cacert certs/root-ca.pem -u admin https://localhost:5601/api/status
```

The same settings can be written in a mounted `opensearch_dashboards.yml`
instead of the variables (see [Configuration](#configuration)). Served over
HTTPS, set `opensearch_security.cookie.secure: true` in that file.


## License

The OpenSearch Dashboards rock is free software, distributed under the Apache Software License, version 2.0. See [LICENSE](licenses/LICENSE-rock) for more information.

## Security, Bugs and feature request

If you find a bug in this rock or want to request a specific feature, here are the useful links:

- Raise the issue or feature request in the [Canonical GitHub repository](https://github.com/canonical/opensearch-artifacts/issues).
- Meet the community and chat with us if there are issues and feature requests in our [Mattermost Channel](https://chat.charmhub.io/charmhub/channels/data-platform).

## Trademark notice

OpenSearch is a registered trademark of Amazon Web Services. Other trademarks are property of their respective owners. OpenSearch Dashboards is not sponsored, endorsed, or affiliated with Amazon Web Services.
