## Developer Guide:


### Installation:
Steps to install it locally:
```
# build and package the snap
snapcraft --debug

# install the snap
sudo snap install opensearch_2.19.6_amd64.snap --dangerous --jailmode
```

### Environment configuration:
Now, configuring the required system settings along with connecting the interfaces, in either of the following ways:

1. Provided [helper script](setup-dev-env.sh):
    ```
    bash setup-dev-env.sh
    ```
2. Manually:
    ```
    # connect interfaces
    sudo snap connect opensearch:log-observe
    sudo snap connect opensearch:mount-observe
    sudo snap connect opensearch:process-control
    sudo snap connect opensearch:system-observe
    sudo snap connect opensearch:sys-fs-cgroup-service
   
    # system configs required by opensearch, should be set using the following way:
    sudo sysctl -w vm.swappiness=0
    sudo sysctl -w vm.max_map_count=262144
    sudo sysctl -w net.ipv4.tcp_retries2=5
    ```

### Set-up an OpenSearch cluster:
The install hook configures and starts a single node cluster, see the [README](README.md).
To reconfigure it:
```
sudo snap run opensearch.setup -Ecluster.name=logs -Enode.roles=cluster_manager,data
sudo snap restart opensearch.daemon
```

### Test your installation:
The OpenSearch setup can be tested either in either of the following ways:
1. Provided [helper script](test-dev-cluster.sh):
    ```
    bash test-dev-cluster.sh    # --admin-auth-password <password> if not the generated one
    ```
2. Manually:
    ```
   # Check if cluster is healthy (green):
   sudo snap run opensearch.test-cluster-health-green
   
   # Check if node is up:
   sudo snap run opensearch.test-node-up
   
   # Check if the security index is well initialised:
   sudo snap run opensearch.test-security-index-created
   ```

### For live debugging:
1. The journal logs:
   ```
   sudo sysctl -w kernel.printk_ratelimit=0 ; journalctl --follow | grep opensearch
   ```
2. Snap logs:
   ```
   snappy-debug scanlog --only-snap=opensearch
   ```
