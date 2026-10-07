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
sudo snap install opensearch-dashboards --channel=3/edge
```

### Starting OpenSearch Dashboards:

The daemon starts as soon as the snap is installed, connecting to an
OpenSearch instance on `https://localhost:9200` with the default credentials
(user: `kibanaserver`, password: `kibanaserver`). Until the OpenSearch CA is
configured, the OpenSearch certificates are not verified
(`opensearch.ssl.verificationMode: none`, the upstream default).

**The OpenSearch snap generates a random `kibanaserver` password and its own CA
on install, so configuring them is a required first step.** Until then,
OpenSearch rejects the default credentials: `http://localhost:5601` answers
`OpenSearch Dashboards server is not ready yet` and the log at the end of this
document shows `[ResponseError]: Response Error`. Snap confinement keeps
Dashboards from reading these files itself; run, as root, the
[example below](#configuration) with the OpenSearch snap on the same machine,
or pass the credentials and CA of your cluster.

The service can be managed with:
```
sudo snap stop|start|restart opensearch-dashboards.opensearch-dashboards-daemon
```

#### Configuration:

The configuration lives in the snap's common data, so it is kept across
refreshes:

```
/var/snap/opensearch-dashboards/common/etc/opensearch-dashboards/opensearch_dashboards.yml
```

It is changed with the `setup` application, which writes the settings to that
file and restarts the daemon. Settings are passed as with the upstream
`bin/opensearch-dashboards`: `--<setting>=<value>`, where `<setting>` is any key
of `opensearch_dashboards.yml`, e.g. `--server.host=0.0.0.0`. Unlike the upstream
command line, the settings are kept in the configuration file.

The value is written as is, as a string, which OpenSearch Dashboards converts to
the type of the setting (e.g. `--server.port=5602`). A value in brackets is a
YAML list, and an empty value removes the setting (e.g. `--server.name=`).
OpenSearch Dashboards refuses to start with an unknown setting
(`Unknown configuration key(s)`): check `snap logs opensearch-dashboards` after a
change.

Two arguments are handled by the snap:

 - `--opensearch.hosts=<host> [<host> ...]` -- the OpenSearch hosts. Further
   arguments and comma separated values are added to the list; the scheme
   defaults to `https://` and the port to `9200`.
 - `--opensearch-ca=<PEM>` -- not a setting: the CA that signed the OpenSearch HTTP certificates. It is
   stored in `.../common/etc/opensearch-dashboards/certificates/opensearch-ca.pem`
   and Dashboards then verifies the OpenSearch certificates against it and
   checks that they are valid for the hosts used
   (`opensearch.ssl.verificationMode: full`, unless set otherwise). The
   certificates of the OpenSearch snap cover `localhost`, the hostname and the
   IP addresses of each node; for certificates that do not, use
   `--opensearch.ssl.verificationMode=certificate` to only check the CA.

For example, with the OpenSearch snap installed on the same machine, which
generates the password of `kibanaserver` and its CA on install:
```
sudo opensearch-dashboards.setup \
    --opensearch.hosts="localhost" \
    --opensearch.password="$(sudo sed -n 's/^kibanaserver: "\(.*\)"$/\1/p' /var/snap/opensearch/common/init_users_pass.yaml)" \
    --opensearch-ca="$(sudo cat /var/snap/opensearch/common/etc/opensearch/certificates/root-ca.pem)"
```

or against a remote cluster:
```
sudo opensearch-dashboards.setup \
    --opensearch.hosts="10.0.0.1" "10.0.0.2" "10.0.0.3:9201" \
    --opensearch-ca="$(cat /path/to/root-ca.pem)" \
    --opensearch.username=kibanaserver --opensearch.password=kibanaserver \
    --server.host=0.0.0.0
```

Run `opensearch-dashboards.setup --help` for the full usage.

#### Keystore:

Secret settings, such as the password of OpenSearch, can be kept out of
`opensearch_dashboards.yml` in the keystore of OpenSearch Dashboards, managed
with the upstream `opensearch-dashboards-keystore` tool through the `keystore`
application. The keystore is
`/var/snap/opensearch-dashboards/common/etc/opensearch-dashboards/opensearch_dashboards.keystore`:

```
sudo opensearch-dashboards.keystore create
echo "<password>" | sudo opensearch-dashboards.keystore add --stdin opensearch.password
sudo opensearch-dashboards.keystore list
sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon
```

#### Plugins:

Plugins are managed with the upstream `opensearch-dashboards-plugin` tool through
the `plugin` application. A plugin must be built for the same version of
OpenSearch Dashboards. Install it from a URL, or from a file in the snap's
common directory, then restart the daemon to load it:

```
sudo opensearch-dashboards.plugin list
sudo opensearch-dashboards.plugin install https://<url>/<plugin>-<version>.zip
sudo cp <plugin>.zip /var/snap/opensearch-dashboards/common/
sudo opensearch-dashboards.plugin install file:///var/snap/opensearch-dashboards/common/<plugin>.zip
sudo opensearch-dashboards.plugin remove <plugin>
sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon
```

The plugins bundled with the snap must remain installed: their removal is
rejected, without changing anything.

The plugins are stored with each snap revision. A refresh removes, from the new
revision only, the custom plugins it cannot load: those built for another
version of OpenSearch Dashboards, those with the id of a bundled plugin, and
those requiring a removed plugin. Reinstall them once available for the new
version. A revert gets back the previous revision's plugins.

### Testing the OpenSearch Dashboards setup:

OpenSearch Dashboards is by default served on http://localhost:5601 (set
`--server.host=0.0.0.0` to expose it on all interfaces).

```
curl -u kibanaserver:kibanaserver http://localhost:5601/api/status
```

Logs are written to:

```
/var/snap/opensearch-dashboards/common/var/log/opensearch-dashboards/opensearch_dashboards.log
```

## License
The OpenSearch Dashboards Snap is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](licenses/LICENSE-snap)
for more information.
