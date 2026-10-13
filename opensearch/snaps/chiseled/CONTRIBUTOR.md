## Developer Guide:


### Installation:
Steps to install it locally:
```
# build and package the snap
snapcraft --debug

# install the snap
sudo snap install opensearch-chiseled_3.8.0_amd64.snap --dangerous --jailmode
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
    sudo snap connect opensearch-chiseled:log-observe
    sudo snap connect opensearch-chiseled:mount-observe
    sudo snap connect opensearch-chiseled:process-control
    sudo snap connect opensearch-chiseled:system-observe
    sudo snap connect opensearch-chiseled:sys-fs-cgroup-service
   
    # system configs required by opensearch, should be set using the following way:
    sudo sysctl -w vm.swappiness=0
    sudo sysctl -w vm.max_map_count=262144
    sudo sysctl -w net.ipv4.tcp_retries2=5
    ```

### Set-up an OpenSearch cluster:
```
# create the certificates
sudo snap run opensearch-chiseled.setup            \
    --node-name cm0                       \
    --node-roles cluster_manager,data     \
    --tls-priv-key-root-pass root1234     \
    --tls-priv-key-admin-pass admin1234   \
    --tls-priv-key-node-pass node1234     \
    --tls-init-setup yes    # this creates the root and admin certs as well.

# start opensearch
sudo snap start opensearch-chiseled.daemon

# initialize the security index
# should only be called once per cluster, or for rebuilding the security index
sudo snap run opensearch-chiseled.security-init --tls-priv-key-admin-pass=admin1234
```

### Test your installation:
The OpenSearch setup can be tested either in either of the following ways:
1. Provided [helper script](test-dev-cluster.sh):
    ```
    # The admin password generated on install (root only):
    ADMIN_PASSWORD=$(sudo sed -n 's/^admin: "\(.*\)"$/\1/p' /var/snap/opensearch-chiseled/common/init_users_pass.yaml)

    bash test-dev-cluster.sh --admin-auth-password "$ADMIN_PASSWORD"
    ```
2. Manually:
    ```
   # Check if cluster is healthy (green):
   sudo snap run opensearch-chiseled.test-cluster-health-green --admin-auth-password "$ADMIN_PASSWORD"
   
   # Check if node is up:
   sudo snap run opensearch-chiseled.test-node-up --node-name "opensearch-$(hostname)" --admin-auth-password "$ADMIN_PASSWORD"
   
   # Check if the security index is well initialised:
   sudo snap run opensearch-chiseled.test-security-index-created --admin-auth-password "$ADMIN_PASSWORD"
   ```

### For live debugging:
1. The journal logs:
   ```
   sudo sysctl -w kernel.printk_ratelimit=0 ; journalctl --follow | grep opensearch
   ```
2. Snap logs:
   ```
   snappy-debug scanlog --only-snap=opensearch-chiseled
   ```
