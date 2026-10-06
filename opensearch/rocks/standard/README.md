## Introduction to OpenSearch Rock (OCI Image)
[![Publish](https://github.com/canonical/opensearch-rock/actions/workflows/release.yaml/badge.svg)](https://github.com/canonical/opensearch-rock/actions/workflows/release.yaml)
[![Build and Test](https://github.com/canonical/opensearch-rock/actions/workflows/ci.yaml/badge.svg)](https://github.com/canonical/opensearch-rock/actions/workflows/ci.yaml)

[OpenSearch](https://opensearch.org/) is an open-source search and analytics suite. 
Developers build solutions for search, data observability, data ingestion and more using OpenSearch. 
OpenSearch is offered under the Apache Software Licence, version 2.0.

[OpenSearch rock](https://github.com/canonical/opensearch-rock/pkgs/container/opensearch) 
is an Open Container Initiative (OCI) image derived from the [OpenSearch Snap](https://snapcraft.io/opensearch). 
The tool used to create this rock is called [Rockcraft](https://canonical-rockcraft.readthedocs-hosted.com/en/latest/index.html).

This repository contains the packaging metadata for creating a OpenSearch rock. This rock image is based on the [OpenSearch Snap](https://github.com/canonical/opensearch-snap)

For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Version
The OpenSearch rock release aligns with the [OpenSearch upstream major version](https://opensearch.org/docs/latest/version-history/) naming. OpenSearch releases major versions such as 1.0, 2.0, and so on.

## Release
Charmed OpenSearch [Rock Release Notes](https://discourse.charmhub.io/t/release-notes-charmed-opensearch-2-rock/10278).


## Rock Usage
### Building the Rock
The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different.
To avoid any issue with other operating systems you can simply build the image with [multipass](https://multipass.run/):
```bash
sudo snap install multipass
multipass launch 22.04 -n rock-dev
multipass shell rock-dev
``` 

#### Clone Repository
```bash
git clone https://github.com/canonical/opensearch-rock.git
cd opensearch-rock
```
#### Installing Prerequisites
```bash
sudo snap install rockcraft --edge --classic
sudo snap install docker
sudo snap install lxd
```
#### Configuring Prerequisites
```bash
sudo usermod -aG docker $USER 
sudo lxd init --auto
```
*_NOTE:_* You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)
#### Packing and Running the Rock
```bash
rockcraft pack

version="$(cat rockcraft.yaml | yq .version)"

rockcraft.skopeo --insecure-policy \
  copy \
  oci-archive:opensearch_"${version}"_amd64.rock \
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
```

`OPENSEARCH_INITIAL_ADMIN_PASSWORD` is optional: without it, a password is
generated (see [Security](#security)).

### Configuration

| Variable | Description |
|---|---|
| `CLUSTER_NAME` | Name of the cluster. Default: `opensearch-dev`. |
| `NODE_NAME` | Name of the node. Default: `node-0`. |
| `NODE_ROLES` | Comma separated roles of the node. Default: `cluster_manager,data`. |
| `INITIAL_CM_NODES` | Comma separated names of the cluster manager eligible nodes that bootstrap a new cluster. |
| `SEED_HOSTS` | Comma separated addresses or names of the nodes to discover the cluster from. |
| `NETWORK_HOST` | Comma separated addresses the node binds to (`network.host`). Default: `0.0.0.0`, like upstream. |

Any other OpenSearch setting can be passed as an environment variable named
after it, like with the upstream image, e.g. `-e cluster.routing.allocation.disk.threshold_enabled=false`.

When OpenSearch fails, e.g. on an invalid configuration, the container exits
instead of restarting it: use a restart policy (`--restart`) to restart it.

### Security

Like the upstream `opensearchproject/opensearch` image, the rock starts with the
security plugin enabled and TLS on both the transport and REST layers. On first
start it runs the security plugin's `install_demo_configuration.sh`, which
installs the demo certificates and sets the password of the `admin` user.

| Variable | Description |
|---|---|
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | Password of the `admin` user. Generated when not set. It must follow the [password format](#password-format). |
| `OPENSEARCH_INITIAL_<USER>_PASSWORD` | Password of the other users of the demo configuration: `ANOMALYADMIN`, `KIBANARO`, `KIBANASERVER`, `LOGSTASH`, `READALL`, `SNAPSHOTRESTORE`, e.g. `OPENSEARCH_INITIAL_KIBANASERVER_PASSWORD`. Generated when not set. It should follow the [password format](#password-format) too. |
| `DISABLE_INSTALL_DEMO_CONFIG` | Set to `true` to skip the demo configuration, e.g. when you mount your own certificates and security configuration. |
| `DISABLE_SECURITY_PLUGIN` | Set to `true` to start OpenSearch with the security plugin disabled (plain HTTP, no authentication). The demo configuration is then skipped and no password is needed. |

#### Password format

The security plugin validates the admin password, like in the upstream image.
It must:

- be between 8 and 100 characters long,
- contain at least one uppercase letter, one lowercase letter, one digit and
  one special character,
- be rated strong by [zxcvbn](https://lowe.github.io/tryzxcvbn),
  which rejects common words and patterns, e.g. `Passw0rd!`,
- not be similar to the user name, e.g. `Adm1n-Something!`.

Otherwise, OpenSearch does not start and the container exits. The reason is in
the logs, which also print the rejected password:

```
Password <password> failed validation: "Password is similar to user name". Please re-try with a minimum 8 character password and must contain at least one uppercase letter, one lowercase letter, one digit, and one special character that is strong. ...
```

The passwords of the other users are not validated on startup. Once the
cluster is up, the security plugin validates the passwords changed through its
REST API with its `plugins.security.restapi.password_*` settings.

The passwords are set on the first start only. The generated ones are stored
in `/usr/share/opensearch/config/init_users_pass.yaml`, readable by the
`opensearch` user only, as `<user>: "<password>"` lines:

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

Unlike the upstream image, `docker exec` runs as `root` by default: run the
tools as the `opensearch` user with `-u opensearch`.

```bash
echo "<value>" | docker exec -i -u opensearch <container> \
  opensearch-keystore add --stdin <setting>
docker exec -u opensearch <container> opensearch-keystore list
```

### Testing a multi nodes deployment:

The nodes find each other by name on a user-defined network. Every node is
given all the node names in `SEED_HOSTS`, so that any of them, including the
first one, can rejoin the cluster after a restart. `data1` is a voting-only
cluster manager eligible node: with 3 voting nodes, the cluster keeps a cluster
manager when any one of them is down.

```
docker network create opensearch-net

common=(
  -d --rm
  --network opensearch-net
  -e OPENSEARCH_INITIAL_ADMIN_PASSWORD="<strong-password>"
  -e SEED_HOSTS=cm0,data1,cm1
  -e INITIAL_CM_NODES=cm0,data1,cm1
)

docker run "${common[@]}" -e NODE_NAME=cm0 \
  -p 9200:9200 --name cm0 opensearch:"${version}"

docker run "${common[@]}" -e NODE_NAME=data1 \
  -e NODE_ROLES=cluster_manager,data,voting_only \
  -p 9201:9200 --name data1 opensearch:"${version}"

docker run "${common[@]}" -e NODE_NAME=cm1 \
  -p 9202:9200 --name cm1 opensearch:"${version}"
```

You now can query the nodes:
```
curl -k -u admin:"<strong-password>" -X GET https://127.0.0.1:9200/_cat/nodes
```
And expect to see 3 nodes.

**NOTE:** This deployment IS NOT suitable for production AS IS, as it secures OpenSearch with the publicly known demo certificates. Please use it as part of the Juju OpenSearch K8s charm once ready.

## License
The OpenSearch rock is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](https://github.com/canonical/opensearch-rock/blob/main/licenses)
for more information.


## Security, Bugs and feature request
If you find a bug in this rock or want to request a specific feature, here are the useful links:
- Raise the issue or feature request in the [Canonical GitHub repository](https://github.com/canonical/opensearch-rock/issues).
- Meet the community and chat with us if there are issues and feature requests in our [Mattermost Channel](https://chat.charmhub.io/charmhub/channels/data-platform).

## Contributing
Please see the [Juju SDK docs](https://juju.is/docs/sdk) for guidelines on enhancements to this charm following best practice guidelines, and [CONTRIBUTING.md](https://github.com/canonical/opensearch-operator/blob/main/CONTRIBUTING.md) for developer guidance.

## Trademark notice
OpenSearch is a registered trademark of Amazon Web Services. Other trademarks are property of their respective owners. OpenSearch is not sponsored, endorsed, or affiliated with Amazon Web Services.

## License
The OpenSearch rock, OpenSearch Snap, and OpenSearch Operator are free software, distributed under the [Apache Software License, version 2.0](https://github.com/canonical/opensearch-rock/blob/main/licenses/LICENSE-rock). They install and operate OpenSearch, which is also licensed under the [Apache Software License, version 2.0](https://github.com/canonical/opensearch-rock/blob/main/licenses/LICENSE-opensearch).
