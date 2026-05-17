# Local Setup

You can bring the cluster up with one Make command or by running the same steps by hand. The two paths produce the same
result.

## With Make

From the repository root:

```bash
make kind-create-local
```

This target runs `scripts/kind_setup.sh create-cluster` followed by `scripts/kind_setup.sh get-secrets`. It creates the
kind cluster, updates Helm dependencies, installs every chart in the right order, exports the Kafka super-user
credentials to `secrets/kafka/`, and writes an `application.yaml` at the repository root for Spring Boot consumers.

To wipe and rebuild:

```bash
make kind-recreate-local
```

This deletes the `lgc` cluster and runs the create target again.

## By hand

The script `scripts/kind_setup.sh` is also runnable directly:

```bash
./scripts/kind_setup.sh create-cluster
./scripts/kind_setup.sh get-secrets
```

If you prefer to drive Helm yourself, the order below mirrors the script. Each step has a reason; do not reorder them.

```bash
# 1. Cluster
kind create cluster --config=./kind/kind-cluster.yaml

# 2. Refresh chart dependencies
helm dep up charts/cert-manager
helm dep up charts/traefik
helm dep up charts/strimzi-kafka-operator
helm dep up charts/strimzi-registry-operator

# 3. cert-manager (must exist before any Certificate or ClusterIssuer)
helm upgrade --install --create-namespace --namespace cert-manager \
  cert-manager charts/cert-manager --atomic

# 4. Traefik (provides the ingress controller and the kafka-mtls TCP entrypoint)
helm upgrade --install --create-namespace --namespace traefik \
  traefik charts/traefik --atomic

# 5. Strimzi operator (reconciles Kafka, KafkaUser, KafkaTopic CRs)
helm upgrade --install --create-namespace --namespace strimzi-kafka-operator \
  strimzi-kafka-operator charts/strimzi-kafka-operator --atomic

# 6. Bridge the mkcert root CA into the cluster as a TLS secret
kubectl create secret tls root-ca-secret \
  --cert="$(mkcert -CAROOT)/rootCA.pem" \
  --key="$(mkcert -CAROOT)/rootCA-key.pem" \
  --namespace=cert-manager

# 7. Schema Registry operator (deployed into the same namespace as the Kafka operator)
helm upgrade --install --namespace strimzi-kafka-operator \
  strimzi-registry-operator charts/strimzi-registry-operator

# 8. dev-glue: ClusterIssuer, Kafka cluster, schema topic, ingress routes
export PROJECT_DOMAIN="local.lgc"
helm upgrade --install --create-namespace --namespace glue \
  glue charts/dev-glue --atomic --set "global.projectDomain=${PROJECT_DOMAIN}"

# 9. Keycloak (depends on the ClusterIssuer for its Ingress)
helm upgrade --install --create-namespace --namespace keycloak \
  keycloak charts/keycloak --atomic --set "global.projectDomain=${PROJECT_DOMAIN}"
```

The `dev-glue` chart is the keystone: it creates the `default-cluster-issuer`, the `Kafka`/`KafkaNodePool`/`KafkaUser`/
`KafkaTopic` CRs, the `StrimziSchemaRegistry`, and the Traefik `IngressRouteTCP` that forwards Kafka traffic on port
9094 by SNI. See [Architecture](../platform-overview/architecture.md) for the full picture.

## Verify

After the setup finishes, check that you are pointing at the right cluster:

```bash
kubectl config current-context     # expected: kind-lgc
```

Wait for the workloads to settle:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n traefik
kubectl get pods -n strimzi-kafka-operator
kubectl get kafka,kafkanodepool,kafkauser,kafkatopic -n glue
kubectl get pods -n keycloak
```

The Kafka pod takes the longest to become ready because it runs through KRaft controller and broker startup. Once
`kubectl get kafka -n glue` reports `Ready=True`, the schema registry pod will start.

For a programmatic health check across the whole stack:

```bash
./scripts/validate-cluster.sh     # or: make validate-cluster
```

## Tear down

```bash
make clean
```

This removes the cluster and all of its volumes. The `secrets/kafka/` directory and `application.yaml` on the host stay
behind; regenerate them with `./scripts/kind_setup.sh get-secrets` after the next create.

## Next

- [Accessing Services](accessing-services.md)
