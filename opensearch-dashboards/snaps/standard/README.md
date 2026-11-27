# OpenSearch Dashboards Snap
[![Publish](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/publish.yaml)
[![Lint](https://github.com/canonical/opensearch-artifacts/actions/workflows/lint.yaml/badge.svg)](https://github.com/canonical/opensearch-artifacts/actions/workflows/lint.yaml)


[//]: # (<h1 align="center">)
[//]: # (  <a href="https://opensearch.org/">)
[//]: # (    <img src="https://opensearch.org/assets/brand/PNG/Logo/opensearch_logo_default.png" alt="OpenSearch" />)
[//]: # (  </a>)
[//]: # (  <br />)
[//]: # (</h1>)

This is the snap package for [OpenSearch Dashboards](https://opensearch.org/docs/latest/dashboards/), a community-driven, Apache 2.0-licensed user interface that lets you visualize your OpenSearch data, together with running and scaling your OpenSearch clusters.


### Installation:
[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/opensearch-dashboards)

or:
```
sudo snap install opensearch-dashboards --channel=2/edge
```

Supported architectures: `amd64` and `arm64`.

### Starting OpenSearch Dashboards:

Neither daemon is started at install time: configure OpenSearch Dashboards
first, then start them with:

```
sudo snap start opensearch-dashboards.opensearch-dashboards-daemon
sudo snap start opensearch-dashboards.exporter-daemon
```

Started this way, they are stopped by refreshes and reboots: add `--enable`
to keep them running across both, e.g.
`sudo snap start --enable opensearch-dashboards.opensearch-dashboards-daemon`.

They are managed with:
```
sudo snap stop|start|restart opensearch-dashboards.opensearch-dashboards-daemon
sudo snap stop|start|restart opensearch-dashboards.exporter-daemon
```

#### Configuration:

All settings are read from the OpenSearch Dashboards configuration file, which
the install hook seeds into writable snap data, copied to the new revision on
each refresh:

```
/var/snap/opensearch-dashboards/current/etc/opensearch-dashboards/opensearch_dashboards.yml
```

The file can be edited directly, or with the `setup` application, which writes
the settings to that file. Settings are passed as with the upstream
`bin/opensearch-dashboards`: `--<setting>=<value>`, where `<setting>` is any key
of `opensearch_dashboards.yml`, e.g. `--server.host=0.0.0.0`. Unlike the upstream
command line, the settings are kept in the configuration file. The daemon must
be (re)started for the new settings to be applied:

```
sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon
```

The value is written as is, as a string, which OpenSearch Dashboards converts to
the type of the setting (e.g. `--server.port=5602`). A value in brackets is a
YAML list, and an empty value removes the setting (e.g. `--server.name=`).
OpenSearch Dashboards refuses to start with an unknown setting
(`Unknown configuration key(s)`): check `snap logs opensearch-dashboards` after a
change. As upstream, OpenSearch Dashboards replaces `${NAME}` in a value by the
environment variable `NAME`, and refuses to start when it is not set. The file
is rewritten: its comments are not kept.

Two arguments are handled by the snap:

 - `--opensearch.hosts=<host> [<host> ...]` -- the OpenSearch hosts. Further
   arguments, comma separated values and the items of a YAML list are added
   to the list; the scheme defaults to `https://` and the port to `9200`.
 - `--opensearch-ca=<PEM>` -- not a setting: the CA that signed the OpenSearch
   HTTP certificates, or several CAs. It is stored in
   `.../current/etc/opensearch-dashboards/certificates/opensearch-ca.pem`, and
   Dashboards then verifies the OpenSearch certificates against it and
   checks that they are valid for the hosts used
   (`opensearch.ssl.verificationMode: full`, unless set otherwise). For
   certificates that are not valid for the hosts used, use
   `--opensearch.ssl.verificationMode=certificate` to only check the CA.
   Node.js does not match an IPv6 address, e.g. `[::1]`, with the addresses of
   a certificate: use a host name for those hosts, or the `certificate` mode.
   The PEM content is a single argument, which the kernel limits to 128 KiB
   (about 50 to 70 certificates).

For example, against a remote cluster:
```
sudo opensearch-dashboards.setup \
    --opensearch.hosts="10.0.0.1" "10.0.0.2" "10.0.0.3:9201" \
    --opensearch-ca="$(cat /path/to/root-ca.pem)" \
    --opensearch.username=kibanaserver --opensearch.password=kibanaserver \
    --server.host=0.0.0.0
sudo snap start opensearch-dashboards.opensearch-dashboards-daemon
```

Run `opensearch-dashboards.setup --help` for the full usage.

The commonly changed keys are:

 - `server.host` -- hostname or IP where the service is exposed (default: `localhost`)
 - `server.port` -- port where the service is exposed (default: `5601`)
 - `opensearch.hosts` -- OpenSearch instance URI to connect to (default: `https://localhost:9200`)
 - `opensearch.username` / `opensearch.password` -- credentials used to
   authenticate against OpenSearch (default: `kibanaserver` / `kibanaserver`)

The Prometheus exporter reads `server.host`, `server.port`,
`opensearch.username` and `opensearch.password` from the configuration file
when it starts: restart it as well after changing them.

#### Keystore:

Secret settings, such as the password of OpenSearch, can be kept out of
`opensearch_dashboards.yml` in the keystore of OpenSearch Dashboards, managed
with the upstream `opensearch-dashboards-keystore` tool through the `keystore`
application. The keystore is
`/var/snap/opensearch-dashboards/current/etc/opensearch-dashboards/opensearch_dashboards.keystore`,
readable only by `snap_daemon`, which runs OpenSearch Dashboards: as upstream,
its content is only obfuscated, not encrypted with a secret. A value of the
keystore takes precedence over the configuration file.

```
sudo opensearch-dashboards.keystore create
echo "<password>" | sudo opensearch-dashboards.keystore add --stdin opensearch.password
sudo opensearch-dashboards.keystore list
sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon
```

The Prometheus exporter only reads the configuration file: keep
`opensearch.username` and `opensearch.password` there when it is used.

### Testing the OpenSearch Dashboards setup:

OpenSearch Dashboards is by default served on http://localhost:5601 (set
`--server.host=0.0.0.0` to expose it on all interfaces).

```
curl -u kibanaserver:kibanaserver http://localhost:5601/api/status
```

The Prometheus exporter serves metrics on http://localhost:9684/metrics.

Logs are written to:

```
/var/snap/opensearch-dashboards/common/var/log/opensearch-dashboards/opensearch_dashboards.log
```

## License
The OpenSearch Dashboards Snap is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](licenses/LICENSE-snap)
for more information.
