# Repository Files

A map of the repository, top-down. The two charts that hold project-specific logic are `dev-glue` and `keycloak`;
everything else is either upstream or orchestration.

## Top level

| Path                     | Purpose                                                                                                    |
|--------------------------|------------------------------------------------------------------------------------------------------------|
| `README.md`              | Original setup notes; the canonical reference for hosts entries and Spring Boot connection settings        |
| `CLAUDE.md`              | Repository guide for AI coding assistants; mirrors much of this documentation                              |
| `Makefile`                     | Local and CI-friendly automation targets for cluster lifecycle, chart validation, and live-cluster health checks |
| `kind/kind-cluster.yaml`       | kind cluster definition: 1 control-plane (with `ingress-ready=true` and host ports 80/443/9094), 3 workers, all pinned to `kindest/node:v1.31.14` via a YAML anchor |
| `scripts/kind_setup.sh`        | Bootstrap, secret extraction, and Spring Boot `application.yaml` generation                                      |
| `scripts/validate-cluster.sh`  | End-to-end health checks (pods, CRs, TLS plumbing, HTTPS endpoints, Kafka mTLS round-trip)                       |
| `scripts/debug-cluster.sh`     | Dumps cluster state into `scripts/debug/<timestamp>/` for diagnosing failures; includes the validate output      |
| `charts/`                | Helm charts (see below)                                                                                    |
| `_backstage/`            | This documentation site (mkdocs + Backstage TechDocs metadata)                                             |
| `_backstage-reference/`  | Reference documentation from a larger sibling project; left in place as a worked example                   |
| `secrets/`               | Generated locally by `get-secrets`. Empty in the repository                                                |

## Charts

| Chart                               | Type                                                | Highlights                                                                                  |
|-------------------------------------|-----------------------------------------------------|---------------------------------------------------------------------------------------------|
| `charts/cert-manager/`              | Wrapper around Jetstack cert-manager v1.20.2        | `installCRDs: true`, Prometheus disabled                                                    |
| `charts/traefik/`                   | Wrapper around Traefik 40.2.0 (app v3.7.1)          | Pinned to `ingress-ready=true` node, host ports 80/443/9094, custom `kafka-mtls` entrypoint |
| `charts/strimzi-kafka-operator/`    | Wrapper around Strimzi 0.46.1                       | `watchAnyNamespace: true`, 512Mi/768Mi memory; KRaft + node-pools enabled per-CR by annotation |
| `charts/strimzi-registry-operator/` | Wrapper around LSST Strimzi Registry Operator 2.1.3 | `clusterName: kafka-lfg`, `clusterNamespace: glue`                                          |
| `charts/dev-glue/`                  | First-party                                         | The keystone chart (Kafka, Schema Registry, ClusterIssuer, Traefik routes)                  |
| `charts/keycloak/`                  | First-party                                         | Keycloak in dev mode with a sandbox realm imported from JSON                                |

### `charts/dev-glue/`

| Path                                         | Resource it produces                              |
|----------------------------------------------|---------------------------------------------------|
| `templates/cert-manager/cluster-issuer.yaml` | `ClusterIssuer default-cluster-issuer`            |
| `templates/kafka/cert.yaml`                  | `Certificate` for `kafka-broker-ca`               |
| `templates/kafka/kafka.yaml`                 | `Kafka kafka-lfg`                                 |
| `templates/kafka/node-pool.yaml`             | `KafkaNodePool default`                           |
| `templates/kafka/user.yaml`                  | `KafkaUser kafka-super-user`                      |
| `templates/kafka/schema-user.yaml`           | `KafkaUser confluent-schema-registry`             |
| `templates/kafka/schema-topic.yaml`          | `KafkaTopic registry-schemas`                     |
| `templates/kafka/schema-registry.yaml`       | `StrimziSchemaRegistry confluent-schema-registry` |
| `templates/kafka/schema-ingress.yaml`        | `Ingress` for `sr.local.lgc`                      |
| `templates/kafka/traefik-port-forward.yaml`  | `IngressRouteTCP` for the `kafka-mtls` entrypoint |

### `charts/keycloak/`

| Path                             | Purpose                                                                                                                                                                               |
|----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `templates/deployment.yaml`      | Keycloak Deployment (`start-dev --import-realm`, hardcoded admin)                                                                                                                     |
| `templates/service.yaml`         | ClusterIP Service on port 8080                                                                                                                                                        |
| `templates/ingress.yaml`         | Ingress for `keycloak.local.lgc`, TLS via `default-cluster-issuer`                                                                                                                    |
| `templates/realm-import-cm.yaml` | ConfigMap rendered from the realm JSON                                                                                                                                                |
| `files/realm-sandbox.json`       | The `sandbox` realm: users `admin`/`reader`/`writer`, groups `admins`/`readers`/`writers`, custom realm roles `admin-action`/`write-action`/`read-action`, public client `sandbox-ui` |

## Generated locally

`get-secrets` writes these files under the repository. They contain credentials and must not be committed.

| Path                         | Contents                                                    |
|------------------------------|-------------------------------------------------------------|
| `secrets/kafka/userpass.txt` | PKCS12 keystore password                                    |
| `secrets/kafka/user.p12`     | Kafka client mTLS identity                                  |
| `secrets/kafka/ca.crt`       | mkcert root + Strimzi cluster CA                            |
| `application.yaml`           | Spring Boot configuration pointing at the three files above |

## Documentation site

| Path                            | Purpose                                                                 |
|---------------------------------|-------------------------------------------------------------------------|
| `_backstage/backstage.yaml`     | Backstage `Component` metadata                                          |
| `_backstage/mkdocs.yml`         | Site configuration (Material theme, mermaid via `pymdownx.superfences`) |
| `_backstage/docker-compose.yml` | Single-service compose file for previewing the site locally             |
| `_backstage/docs/`              | Markdown sources for the pages in the navigation                        |
