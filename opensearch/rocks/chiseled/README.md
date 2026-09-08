# OpenSearch Chiseled rock
[![Publish artifacts](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)

This directory contains the packaging metadata for creating a chiseled rock of [OpenSearch](https://opensearch.org/) built from the [opensearch-chiseled snap](../../snaps/chiseled). A rock is an Open Container Initiative (OCI) image; for more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

Unlike the standard and charmed rocks, this image ships only the
`opensearch-security` plugin — every other bundled plugin is removed while
building the snap, including `opensearch-knn` and
`opensearch-performance-analyzer`. As a consequence this rock does not relocate
the k-NN native libraries and does not add them to `java.library.path`.

The image is built for `amd64` and `arm64`, runs as the unprivileged `_daemon_`
user, and is published to the GitHub Container Registry:

```bash
docker pull ghcr.io/canonical/opensearch-chiseled:3.7.0-26.04_edge
```

## Running the rock
The Pebble service `opensearch` starts on boot and configures the node from
environment variables:

| Variable            | Default                | Description                                        |
| ------------------- | ---------------------- | -------------------------------------------------- |
| `CLUSTER_NAME`      | `opensearch-dev`       | `cluster.name`                                     |
| `NODE_NAME`         | `node-0`               | `node.name`                                        |
| `NODE_ROLES`        | `cluster_manager,data` | Comma-separated `node.roles`                       |
| `INITIAL_CM_NODES`  | unset                  | Comma-separated `cluster.initial_cluster_manager_nodes` |
| `SEED_HOSTS`        | unset                  | Comma-separated `discovery.seed_hosts`             |
| `NETWORK_HOST`      | `_local_,_site_`       | Comma-separated `network.host`                     |

```bash
docker run -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  ghcr.io/canonical/opensearch-chiseled:3.7.0-26.04_edge

curl -XGET http://127.0.0.1:9200
```

**NOTE:** the entrypoint sets `plugins.security.disabled: true`, so the REST API
is served over plain HTTP. This image IS NOT suitable for production AS IS.
Use it through the OpenSearch K8s charm, which configures security.

## Building the rock
The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different.

### Clone Repository
```bash
git clone git@github.com:canonical/opensearch-artifacts.git
cd opensearch-artifacts/opensearch/rocks/chiseled
```
### Installing Prerequisites
```bash
sudo snap install rockcraft --edge --classic
sudo snap install docker
sudo snap install lxd
```
### Configuring Prerequisites
```bash
sudo usermod -aG docker $USER
sudo lxd init --auto

# required by OpenSearch on the host
sudo sysctl -w vm.swappiness=0
sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w net.ipv4.tcp_retries2=5
```
*_NOTE:_* You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)
### Packing and Running the rock
```bash
rockcraft pack

version="$(yq .version rockcraft.yaml | tr -d '"')"
arch="$(dpkg --print-architecture)"

rockcraft.skopeo --insecure-policy copy \
  oci-archive:opensearch-chiseled_"${version}"_"${arch}".rock \
  docker-daemon:opensearch-chiseled:"${version}"

docker run -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch-chiseled:"${version}"
```

The rock stages the snap from the `3/edge` channel, so a local build picks up
whatever revision is currently live on the store.

## Testing the rock
This variant ships a [spread](https://github.com/canonical/spread) smoke suite
that forms a three-node cluster (`cm0`, `cm1`, `data1`) in Docker and asserts
that all three nodes join. It runs against a `craft` (LXD) backend on
`ubuntu-26.04`:

```bash
rockcraft test
```

## License
The OpenSearch Chiseled rock is free software, distributed under the Apache
Software License, version 2.0. See [LICENSE](../../../LICENSE) and the
[licenses](licenses) directory, which also contains the upstream OpenSearch
licence.

## Trademark notice

OpenSearch is a registered trademark of Amazon Web Services. Other trademarks are property of their respective owners. OpenSearch is not sponsored, endorsed, or affiliated with Amazon Web Services.
