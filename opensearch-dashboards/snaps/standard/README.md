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
file and restarts the daemon. Settings are passed as `-E<SETTING>=<VALUE>`,
where `<SETTING>` follows the upstream OpenSearch Dashboards tarball
conventions:

 - a configuration key, as passed to `bin/opensearch-dashboards --<key>=<value>`,
   e.g. `-Eserver.host=0.0.0.0`
 - the upstream docker environment variable of that key, e.g.
   `-ESERVER_HOST=0.0.0.0` or `-EOPENSEARCH_USERNAME=kibanaserver`
 - the same variable without its `OPENSEARCH_` prefix, e.g. `-EUSERNAME=kibanaserver`

Two settings are specific to the snap:

 - `-EHOSTS=<host> [<host> ...]` -- the OpenSearch hosts (`opensearch.hosts`).
   Further arguments are added to the list; the scheme defaults to `https://`
   and the port to `9200`.
 - `-ECA=<PEM>` -- the CA that signed the OpenSearch HTTP certificates. It is
   stored in `.../common/etc/opensearch-dashboards/certificates/opensearch-ca.pem`
   and Dashboards then verifies the OpenSearch certificates against it
   (`opensearch.ssl.verificationMode: certificate`, unless set otherwise).

For example, with the OpenSearch snap installed on the same machine:
```
sudo opensearch-dashboards.setup \
    -EHOSTS="localhost" \
    -ECA="$(sudo cat /var/snap/opensearch/current/etc/opensearch/certificates/root-ca.pem)"
```

or against a remote cluster:
```
sudo opensearch-dashboards.setup \
    -EHOSTS="10.0.0.1" "10.0.0.2" "10.0.0.3:9201" \
    -ECA="$(cat /path/to/root-ca.pem)" \
    -EUSERNAME=kibanaserver -EPASSWORD=kibanaserver \
    -ESERVER_HOST=0.0.0.0 \
    -Eopensearch.ssl.verificationMode=full
```

Run `opensearch-dashboards.setup --help` for the full usage.

### Testing the OpenSearch Dashboards setup:

OpenSearch Dashboards is by default served on http://localhost:5601 (set
`-ESERVER_HOST=0.0.0.0` to expose it on all interfaces).

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
