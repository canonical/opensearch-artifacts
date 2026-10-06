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

`OPENSEARCH_INITIAL_ADMIN_PASSWORD` is optional: without it, a password is
generated (see [Security](#security)).

### Security

Like the upstream `opensearchproject/opensearch` image, the rock starts with the
security plugin enabled and TLS on both the transport and REST layers. On first
start it runs the security plugin's `install_demo_configuration.sh`, which
installs the demo certificates and sets the password of the `admin` user.

| Variable | Description |
|---|---|
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | Password of the `admin` user. Generated when not set. It must be at least 8 characters long, contain an uppercase letter, a lowercase letter, a digit and a special character, and be rated strong by [zxcvbn](https://lowe.github.io/tryzxcvbn). |
| `OPENSEARCH_INITIAL_<USER>_PASSWORD` | Password of the other users of the demo configuration: `ANOMALYADMIN`, `KIBANARO`, `KIBANASERVER`, `LOGSTASH`, `READALL`, `SNAPSHOTRESTORE`, e.g. `OPENSEARCH_INITIAL_KIBANASERVER_PASSWORD`. Generated when not set. |
| `DISABLE_INSTALL_DEMO_CONFIG` | Set to `true` to skip the demo configuration, e.g. when you mount your own certificates and security configuration. |
| `DISABLE_SECURITY_PLUGIN` | Set to `true` to start OpenSearch with the security plugin disabled (plain HTTP, no authentication). The demo configuration is then skipped and no password is needed. |

The passwords are set on the first start only. The generated ones are stored
in `/usr/share/opensearch/config/init_users_pass.yaml`, readable by the
`_daemon_` user only, as `<user>: "<password>"` lines:

```bash
docker exec <container> cat /usr/share/opensearch/config/init_users_pass.yaml
```

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
container_0_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_0_id}")

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
container_1_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_1_id}")

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

**NOTE:** This deployment IS NOT suitable for production AS IS, as it secures OpenSearch with the publicly known demo certificates. Please use it as part of the Juju OpenSearch K8s charm once ready.

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
