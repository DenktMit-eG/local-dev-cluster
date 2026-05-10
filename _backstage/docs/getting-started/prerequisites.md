# Prerequisites

Before bringing up the cluster, install the tools below and run mkcert once to create a trusted local certificate
authority.

## Required tools

| Tool                                               | Purpose                                                | Verify                     |
|----------------------------------------------------|--------------------------------------------------------|----------------------------|
| [Docker](https://www.docker.com/)                  | Runs the kind nodes as containers                      | `docker version`           |
| [kind](https://kind.sigs.k8s.io/)                  | Creates the local Kubernetes cluster                   | `kind version`             |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Talks to the cluster                                   | `kubectl version --client` |
| [Helm](https://helm.sh/docs/intro/install/)        | Installs the charts in this repo                       | `helm version`             |
| [mkcert](https://github.com/FiloSottile/mkcert)    | Creates a locally trusted root CA used by cert-manager | `mkcert -version`          |
| [Earthly](https://earthly.dev/) (optional)         | One-command cluster lifecycle                          | `earthly --version`        |

Earthly is optional. The same steps can be run by hand using `helm` and `kubectl`. See [Local Setup](local-setup.md).

## Install the local root CA

mkcert generates a development root CA and adds it to the trust store of your machine and your browsers. cert-manager
then uses that root to issue leaf certificates for cluster ingresses, which is why services on `*.local.lgc` show up as
trusted in your browser.

```bash
mkcert -install
```

The root CA and key live under `$(mkcert -CAROOT)`. The cluster setup reads them from there to create the
`root-ca-secret` in the `cert-manager` namespace.

If you skip this step, the cluster still comes up, but every browser request to a `*.local.lgc` address shows a
certificate warning.

## Free host ports

The kind cluster maps three ports from the control-plane node to the host:

| Port | Used for                           |
|------|------------------------------------|
| 80   | HTTP traffic to Traefik            |
| 443  | HTTPS traffic to Traefik           |
| 9094 | Kafka mTLS via Traefik TCP routing |

Stop any service that is already bound to these ports before creating the cluster.

## Hosts file

Several services are reachable through Traefik on locally resolved hostnames. Add the following lines to `/etc/hosts` (
or the Windows equivalent). They are also listed on [Accessing Services](accessing-services.md).

```
127.0.0.1   keycloak.local.lgc
127.0.0.1   sr.local.lgc
127.0.0.1   bootstrap.local.lgc
127.0.0.1   b0.local.lgc
```

## Next

- [Local Setup](local-setup.md)
