# Charmed OpenSearch Dashboards Snap
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
[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/opensearch-dashboards-charmed)

or:
```
sudo snap install opensearch-dashboards-charmed --channel=3/edge
```

### Starting OpenSearch Dashboards:

#### Configuration:

Most settings are read from the OpenSearch Dashboards configuration file, which
the install hook seeds into writable snap data:

```
/var/snap/opensearch-dashboards-charmed/current/etc/opensearch-dashboards/opensearch_dashboards.yml
```

Edit that file before starting the service. The commonly changed keys are:

 - `server.host` -- hostname or IP where the service is exposed (default: `localhost`)
 - `server.port` -- port where the service is exposed (default: `5601`)
 - `opensearch.hosts` -- OpenSearch instance URI to connect to (default: `https://localhost:9200`)
 - `opensearch.username` / `opensearch.password` -- credentials used to
   authenticate against OpenSearch (default: `kibanaserver` / `kibanaserver`)

In addition, the snap exposes a single snap option, used by the bundled
Prometheus exporter when it connects to Dashboards:

 - `scheme` -- `http` or `https` (default: `http`)

```
sudo snap set opensearch-dashboards-charmed scheme=https
```

#### Starting up the service:

Once the configuration is in place (or if the defaults are acceptable),
`opensearch-dashboards-charmed` can be started by executing the following command
```
sudo snap start opensearch-dashboards-charmed.opensearch-dashboards-daemon
```

### Testing the OpenSearch Dashboards setup:

OpenSearch Dashboards is by default started up at http://localhost:5601, with default
credentials (user: `kibanaserver`, password: `kibanaserver`).

If you have an OpenSearch instance running with default settings (https://localhost:9200),
the Dashboard should be able to automatically connect.

Any other potential connection (or other configuration information) should go into the
`opensearch_dashboards.yml` file described in
[Configuration](#configuration) above.

## License
The Charmed OpenSearch Dashboards Snap is free software, distributed under the Apache
Software License, version 2.0. See
[LICENSE](licenses/LICENSE-snap)
for more information.
