# Commands

A short list of the commands you actually use. For full procedures see [Local Setup](../getting-started/local-setup.md)
and [Operations](../operations/recreate-cluster.md).

## Cluster lifecycle

```bash
make kind-create-local          # create cluster, install charts, extract secrets
make kind-recreate-local        # delete and rebuild
make validate                   # helm lint + helm template
make validate-cluster           # end-to-end checks against the running cluster
make debug-cluster              # dump full cluster state under scripts/debug/<timestamp>/
make clean                      # delete cluster and remove generated secrets
make clean-secrets              # only remove secrets/ and application.yaml
kind get clusters               # list local kind clusters
kubectl config current-context  # expected: kind-lgc
```

## Setup script

```bash
./scripts/kind_setup.sh create-cluster   # bring up the cluster
./scripts/kind_setup.sh get-secrets      # write secrets/kafka/* and application.yaml
./scripts/kind_setup.sh delete-cluster   # delete the cluster
./scripts/validate-cluster.sh            # green/red health snapshot
./scripts/debug-cluster.sh               # capture state to scripts/debug/<timestamp>/
```

## Helm

```bash
helm dep up charts/cert-manager
helm dep up charts/traefik
helm dep up charts/strimzi-kafka-operator
helm dep up charts/strimzi-registry-operator
helm list -A
helm lint charts/dev-glue
helm template glue charts/dev-glue --set global.projectDomain=local.lgc
helm upgrade --install -n glue glue charts/dev-glue \
  --set global.projectDomain=local.lgc --atomic
```

## Inspection

```bash
kubectl get pods -A
kubectl get ingress,ingressroutetcp -A

kubectl get kafka,kafkanodepool -n glue
kubectl get kafkauser,kafkatopic -n glue
kubectl get strimzischemaregistry -n glue

kubectl get certificate -A
kubectl get clusterissuer

kubectl logs -n glue deploy/confluent-schema-registry
kubectl logs -n glue -l strimzi.io/cluster=kafka-lfg,strimzi.io/kind=Kafka
kubectl logs -n keycloak deploy/keycloak
```

## Quick external probes

```bash
curl -sI https://keycloak.local.lgc | head -1
curl -s  https://sr.local.lgc/subjects
openssl s_client -connect bootstrap.local.lgc:9094 \
  -servername bootstrap.local.lgc < /dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer
```

## Documentation preview

```bash
cd _backstage
docker compose up
```

The site serves at `http://localhost:8000/`.
