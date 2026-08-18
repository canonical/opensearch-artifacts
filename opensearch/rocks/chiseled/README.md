# OpenSearch Chiseled Rock (OCI Image)

[OpenSearch](https://opensearch.org/) is an open-source search and analytics suite. Developers build solutions for search, data observability, data ingestion and more using OpenSearch. OpenSearch is offered under the Apache Software Licence, version 2.0.

The [Chiseled OpenSearch rock](https://github.com/canonical/opensearch-artifacts) is an Open Container Initiative (OCI) image derived from the [opensearch-chiseled Snap](https://snapcraft.io/opensearch-chiseled). The tool used to create this rock is called [Rockcraft](https://canonical-rockcraft.readthedocs-hosted.com/en/latest/index.html).

This repository contains the packaging metadata for creating the Chiseled OpenSearch rock. This rock image is based on the [opensearch-chiseled Snap](https://github.com/canonical/opensearch-artifacts/tree/2/edge/opensearch/snaps/chiseled).

For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Bundled plugins

Unlike the standard and charmed rocks, this image ships only the `opensearch-security` plugin. Every other bundled plugin is removed while building the [opensearch-chiseled Snap](https://github.com/canonical/opensearch-artifacts/tree/2/edge/opensearch/snaps/chiseled), including `opensearch-knn` and `opensearch-performance-analyzer`. As a consequence this rock does not relocate the k-NN native libraries and does not add them to `java.library.path`.

## Version

The Chiseled OpenSearch rock release aligns with the [OpenSearch upstream major version](https://opensearch.org/docs/latest/version-history/) naming. OpenSearch releases major versions such as 1.0, 2.0, and so on.

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
cd opensearch-artifacts/opensearch/rocks/chiseled

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
  oci-archive:opensearch-chiseled_"${version}"_"${arch}".rock \
  docker-daemon:opensearch-chiseled:"${version}"

docker run \
  -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch-chiseled:"${version}"

### Testing a multi nodes deployment:

```
# create first cm_node container
container_0_id=$(docker run \
  -d --rm -it \
  -e NODE_NAME=cm0 \
  -e INITIAL_CM_NODES=cm0 \
  -p 9200:9200 \
  --name cm0 \
  opensearch-chiseled:"${version}")
container_0_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_0_id}")

# wait a bit for it to fully initialize
sleep 15s

# create data/voting_only node container
container_1_id=$(docker run \
    -d --rm -it \
    -e NODE_NAME=data1 \
    -e SEED_HOSTS="${container_0_ip}" \
    -e NODE_ROLES=data,voting_only \
    -p 9201:9200 \
    --name data1 \
    opensearch-chiseled:"${version}")
container_1_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${container_1_id}")

# wait a bit for it to fully initialize
sleep 15s

# create 2nd cm_node container
container_2_id=$(docker run \
    -d --rm -it \
    -e NODE_NAME=cm1 \
    -e SEED_HOSTS="${container_0_ip},${container_1_ip}" \
    -e INITIAL_CM_NODES="cm0,cm1" \
    -p 9202:9200 \
    --name cm1 \
    opensearch-chiseled:"${version}")

# wait a bit for it to fully initialize
sleep 15s
```

You now can query the nodes:

```
curl -X GET http://127.0.1.1:9200/_nodes/
```

And expect to see 3 nodes.

**NOTE:** This deployment IS NOT suitable for production AS IS. As this deployment disables and does NOT configure the security of OpenSearch. Please use it as part of the Juju OpenSearch K8s charm once ready.

## License

The Chiseled OpenSearch rock is free software, distributed under the Apache Software License, version 2.0. See [LICENSE](https://github.com/canonical/opensearch-artifacts/blob/main/LICENSE) for more information.

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
