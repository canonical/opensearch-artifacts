# OpenSearch Dashboards Rock

This repository contains the packaging metadata for creating an OpenSearch Dashboards rock derived from the [OpenSearch Dashboards Snap](https://github.com/canonical/opensearch-dashboards-snap). For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Building the rock
The steps outlined below are based on the assumption that you are building the rock with the latest LTS of Ubuntu.  
If you are using another version of Ubuntu or another operating system, the process may be different.

### Clone Repository
```bash
git clone git@github.com:canonical/opensearch-dashboards-rock.git
cd opensearch-dashboards-rock
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
```
*_NOTE:_* You will need to open a new shell for the group change to take effect (i.e. `su - $USER`)
### Packing and Running the rock

```
rockcraft pack

ROCK=$(echo ./opensearch-dashboards_*.rock)
version=$(yq .version rockcraft.yaml)

sudo rockcraft.skopeo --insecure-policy \
  copy \
  oci-archive:"${ROCK}" \
  docker-daemon:opensearch-dashboards:"${version}"

docker run \
  -d --rm \
  -p 127.0.0.1:5601:5601 \
  -e OPENSEARCH_HOSTS="[http://<your-opensearch-host>:<port>]" \
  opensearch-dashboards:${version}
```
### Example alongside containerized OpenSearch
```
version=$(yq .version rockcraft.yaml)
base=$(yq .base rockcraft.yaml)
docker pull ghcr.io/canonical/charmed-opensearch:${version}-${base#*@}_edge

opensearch_cont=$(docker run -d --rm \
    --name cm0 \
    -p 127.0.0.1:9200:9200 \
    -e NODE_NAME=cm0 \
    -e INITIAL_CM_NODES=cm0 \
    ghcr.io/canonical/charmed-opensearch:${version}-${base#*@}_edge
)
opensearch_cont_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${opensearch_cont}")

docker run -d --rm \
    -p 127.0.0.1:5601:5601 \
    -p 127.0.0.1:9684:9684 \
    -e OPENSEARCH_HOSTS="[http://${opensearch_cont_ip}:9200]" \
    opensearch-dashboards:${version}
```
OpenSearch Dashboards will now be accessible at http://localhost:5601. The Prometheus exporter can be reached at http://localhost:9684.

## License:
The OpenSearch Dashboards rock is free software, distributed under the Apache Software License, version 2.0. See licenses for 
more information.
