# Components

The cluster is six charts: four thin wrappers around upstream charts and two first-party charts. The first-party
charts (`dev-glue` and `keycloak`) hold the project-specific configuration.

| Chart                              | Type        | Upstream version                         | Namespace                | Role                                                                         |
|------------------------------------|-------------|------------------------------------------|--------------------------|------------------------------------------------------------------------------|
| `charts/cert-manager`              | wrapper     | `cert-manager` 1.14.2 (Jetstack)         | `cert-manager`           | Issues TLS certificates from a `ClusterIssuer`                               |
| `charts/traefik`                   | wrapper     | `traefik` 26.0.0                         | `traefik`                | Ingress controller and TCP entrypoint for Kafka                              |
| `charts/strimzi-kafka-operator`    | wrapper     | `strimzi-kafka-operator` 0.38.0          | `strimzi-kafka-operator` | Reconciles `Kafka`, `KafkaUser`, `KafkaTopic`, `KafkaNodePool` CRs           |
| `charts/strimzi-registry-operator` | wrapper     | `strimzi-registry-operator` 2.1.0 (LSST) | `strimzi-kafka-operator` | Reconciles `StrimziSchemaRegistry` CRs                                       |
| `charts/dev-glue`                  | first-party | 0.1.0                                    | `glue`                   | Wires the operators into a working Kafka, Schema Registry, and ingress setup |
| `charts/keycloak`                  | first-party | 0.1.0, app 23.0.4                        | `keycloak`               | Runs Keycloak in dev mode with the `sandbox` realm                           |

## cert-manager

Installed first because the rest of the platform expects `Certificate` and `ClusterIssuer` CRDs to exist. The wrapper
enables `installCRDs: true` and disables Prometheus metrics. The actual `ClusterIssuer` (`default-cluster-issuer`) is
created later by `dev-glue` and points at `root-ca-secret`, which the setup script populates from the developer's local
mkcert root.

## Traefik

Pinned to the control-plane node via `nodeSelector: ingress-ready: "true"` and tolerations for the `master` and
`control-plane` taints. The chart is configured with three host ports on the deployment, with the upstream `service`
resource disabled because the kind config maps the host ports directly to the control-plane container:

| Entrypoint   | Port | Purpose                                       |
|--------------|------|-----------------------------------------------|
| `web`        | 80   | Plain HTTP                                    |
| `websecure`  | 443  | HTTPS termination for Ingress resources       |
| `kafka-mtls` | 9094 | TLS-passthrough TCP routing for Kafka clients |

## Strimzi Kafka Operator

Watches all namespaces (`watchAnyNamespace: true`) and runs with the feature gates `+KafkaNodePools`, `+UseKRaft`,
`+UnidirectionalTopicOperator`. The single-replica deployment is enough for a local cluster.

## Strimzi Registry Operator

Configured with `clusterName: kafka-lfg` and `clusterNamespace: glue`. It is installed into the `strimzi-kafka-operator`
namespace alongside the Kafka operator; that is intentional and matches the upstream chart's `operatorNamespace`
default.

The operator's Custom Resource is `StrimziSchemaRegistry` (apiGroup `roundtable.lsst.codes/v1beta1`). Despite the name,
the operator does not implement a registry of its own. It deploys the standard Confluent Schema Registry image (
`confluentinc/cp-schema-registry`, version controlled by `spec.registryImageTag`) and wires it to a Strimzi-managed
Kafka cluster using a Strimzi `KafkaUser`. The "Strimzi" in the CR name refers to that integration, not to the registry
implementation.

## dev-glue

The keystone chart. Its templates create the following resources in the `glue` namespace, all of which depend on
operators or CRDs installed earlier:

| Template                           | Resource                                          | Notes                                                                                                                             |
|------------------------------------|---------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| `cert-manager/cluster-issuer.yaml` | `ClusterIssuer default-cluster-issuer`            | Backed by `root-ca-secret` in the `cert-manager` namespace                                                                        |
| `kafka/cert.yaml`                  | `Certificate`                                     | Issues the `kafka-broker-ca` secret with SANs `bootstrap.local.lgc` and `b0.local.lgc`                                            |
| `kafka/kafka.yaml`                 | `Kafka kafka-lfg`                                 | Three listeners: `plain` (9092 internal SCRAM), `tls` (9093 internal mTLS), `external` (9094 cluster-ip mTLS, fronted by Traefik) |
| `kafka/node-pool.yaml`             | `KafkaNodePool default`                           | One replica with combined `controller` + `broker` roles, 1 CPU / 1 GiB, 20 GiB JBOD storage                                       |
| `kafka/user.yaml`                  | `KafkaUser kafka-super-user`                      | mTLS identity; granted superuser by `Kafka.spec.kafka.authorization.superUsers`                                                   |
| `kafka/schema-user.yaml`           | `KafkaUser confluent-schema-registry`             | mTLS with ACLs scoped to the `registry-schemas` topic and `schema-registry*` consumer groups                                      |
| `kafka/schema-topic.yaml`          | `KafkaTopic registry-schemas`                     | One partition, compacted; `replicas: 3` is set even though the cluster has one broker                                             |
| `kafka/schema-registry.yaml`       | `StrimziSchemaRegistry confluent-schema-registry` | Image tag `7.6.0`, listener `tls`, `securityProtocol: SSL`                                                                        |
| `kafka/schema-ingress.yaml`        | `Ingress`                                         | Routes `sr.local.lgc` to the `confluent-schema-registry` Service on port 8081, TLS issued by the cluster issuer                   |
| `kafka/traefic-port-forward.yaml`  | `IngressRouteTCP`                                 | Routes the `kafka-mtls` entrypoint to the bootstrap and broker Services using SNI; TLS is passed through, not terminated          |

The `replicas: 3` on the schema topic is a known mismatch with the single-broker cluster. Strimzi creates the topic
regardless because the broker default is `min.insync.replicas: 1`; raising broker count to three is the recommended fix
when this becomes a real concern.

## Keycloak

Runs the upstream image `quay.io/keycloak/keycloak:23.0.4` in development mode (`start-dev --import-realm`) with
hardcoded admin credentials (`admin` / `admin`). The realm is supplied through a ConfigMap rendered from
`charts/keycloak/files/realm-sandbox.json`, so each pod restart re-imports it. Suitable only for local development.

## Next

- [Network and TLS](network-and-tls.md)
- [Keycloak Sandbox](../developer-guide/keycloak-sandbox.md)
