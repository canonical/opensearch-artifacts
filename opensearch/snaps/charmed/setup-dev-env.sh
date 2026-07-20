#!/usr/bin/env bash


# Use sudo only when not running as root (spread VMs run as root,
# local dev runs as a normal user).
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi


function connect_interfaces () {
    $SUDO snap connect opensearch-charmed:log-observe
    $SUDO snap connect opensearch-charmed:mount-observe
    $SUDO snap connect opensearch-charmed:process-control
    $SUDO snap connect opensearch-charmed:system-observe
    $SUDO snap connect opensearch-charmed:sys-fs-cgroup-service
    # shmem-perf-analyzer is only available where the snap has been
    # given access to a shared-memory slot; tolerate absence.
    $SUDO snap connect opensearch-charmed:shmem-perf-analyzer || true
}


function set_kernel_conf () {
    # 1. Allow the opensearch user to Disable all swap files:
    # swapon -a -- default in local machine
    $SUDO sysctl -w vm.swappiness=0

    # 2. Ensuring sufficient virtual memory: https://www.elastic.co/guide/en/elasticsearch/reference/current/vm-max-map-count.html
    # sysctl -w vm.max_map_count=65530 -- default in local machine
    $SUDO sysctl -w vm.max_map_count=262144

    # 3. Reduce TCP retransmission timeout = ~6 seconds
    # sysctl -w net.ipv4.tcp_retries2=15 -- default in local machine
    $SUDO sysctl -w net.ipv4.tcp_retries2=5
}


connect_interfaces
set_kernel_conf
