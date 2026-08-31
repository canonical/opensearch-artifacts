## Developer Guide:


### Set up opensearch

We recommend to install the opensearch snap, so that opensearch-dashboards
has an opensearch instance to connect to.

Instructions to get the opensearch snap working are detailed in the
[OpenSearch snap README](../../../opensearch/snaps/standard/README.md).


### Installation:
Steps to package and install `opensearch-dashboards` snap locally (having checked out this repo):

```
cd opensearch-dashboards/snaps/standard

# build and package the snap
snapcraft pack --debug

# install the snap
sudo snap install ./opensearch-dashboards_3.7.0_amd64.snap --dangerous --jailmode
```


## Start opensearch-dashboards

As explained in the
[README: Starting OpenSearch Dashboards](README.md#starting-opensearch-dashboards)

### Test your installation:

As explained in the
[README: Testing the OpenSearch Dashboards setup](README.md#testing-the-opensearch-dashboards-setup)

### For live debugging:
1. The journal logs:
   ```
   sudo sysctl -w kernel.printk_ratelimit=0 ; journalctl --follow | grep opensearch-dashboards
   ```
2. Snap logs:
   ```
   snap logs opensearch-dashboards -n=50 -f
   ```
3. Denials reported by snap confinement:
   ```
   snappy-debug scanlog --only-snap=opensearch-dashboards
   ```
