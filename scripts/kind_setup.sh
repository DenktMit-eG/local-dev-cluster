#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
SECRETS_DIR="${REPO_ROOT}/secrets"
PROJECT_DOMAIN="${PROJECT_DOMAIN:-local.lgc}"

cd "${REPO_ROOT}"
mkdir -p "${SECRETS_DIR}"

FAIL() {
  echo "error: $*" >&2
  exit 1
}

CHECK_COMMAND() {
  if ! hash "$1" 2>/dev/null; then
    FAIL "$1 not installed"
  fi
}

CHECK_PREREQUISITES() {
  CHECK_COMMAND kubectl
  CHECK_COMMAND helm
  CHECK_COMMAND mkcert
  CHECK_COMMAND docker
  CHECK_COMMAND kind
}

CHECK_HELM() {
  CHECK_COMMAND helm
}

CHECK_KIND() {
  CHECK_COMMAND kind
}

CHECK_SECRET_PREREQUISITES() {
  CHECK_COMMAND kubectl
  CHECK_COMMAND mkcert
}

KIND_UPDATE_DEPENDENCIES() {
    CHECK_HELM
    helm dep up charts/strimzi-kafka-operator
    helm dep up charts/strimzi-registry-operator
    helm dep up charts/traefik
    helm dep up charts/cert-manager
}

# Function to create kind cluster and setup helm charts.
# --timeout 15m on every install: fresh kind workers can take >5m (the default) just to pull
# the Strimzi operator image (~200MB), and an atomic rollback at that point loses useful logs.
KIND_CREATE_CLUSTER() {
    CHECK_PREREQUISITES
    kind create cluster --config=./kind/kind-cluster.yaml
    KIND_UPDATE_DEPENDENCIES
    helm upgrade --install --create-namespace --namespace cert-manager cert-manager charts/cert-manager --atomic --timeout 15m
    helm upgrade --install --create-namespace --namespace traefik traefik charts/traefik --atomic --timeout 15m
    helm upgrade --install --create-namespace --namespace strimzi-kafka-operator strimzi-kafka-operator charts/strimzi-kafka-operator --atomic --timeout 15m
    kubectl create secret tls root-ca-secret \
      --cert="$(mkcert -CAROOT)/rootCA.pem" \
      --key="$(mkcert -CAROOT)/rootCA-key.pem" \
      --namespace=cert-manager
    helm upgrade --install -n strimzi-kafka-operator strimzi-registry-operator charts/strimzi-registry-operator --atomic --timeout 15m
    helm upgrade --create-namespace --install -n glue glue ./charts/dev-glue --atomic --timeout 15m --set "global.projectDomain=${PROJECT_DOMAIN}"
    helm upgrade --install --create-namespace --atomic --timeout 15m --namespace keycloak keycloak ./charts/keycloak --set "global.projectDomain=${PROJECT_DOMAIN}"
}

KIND_DELETE_CLUSTER() {
    CHECK_KIND
    kind delete cluster --name lgc
}

# Function to retrieve secrets for Kafka
KIND_GET_SECRETS() {
    CHECK_SECRET_PREREQUISITES
    mkdir -p "${SECRETS_DIR}/kafka"
    # The KafkaUser Secret is created by the Strimzi entity-operator after the Kafka cluster
    # comes up; on a cold first install (no cached images) that can take several minutes.
    # Wait on the actual readiness condition rather than a fixed sleep.
    echo "Waiting for kafka-super-user to become Ready (up to 10 minutes)..."
    kubectl -n glue wait --for=condition=Ready --timeout=10m kafkauser/kafka-super-user
    # Once Ready, the Secret is written but there is still a short kube-controller-manager
    # race (PR kubernetes/kubernetes#122994 fixed it in 1.31 then was reverted in #125630)
    # where the Secret can come back without all data fields. A small sleep covers this.
    sleep 5
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.user\.password}' | base64 -d > "${SECRETS_DIR}/kafka/userpass.txt" && \
    cat "$(mkcert -CAROOT)/rootCA.pem" > "${SECRETS_DIR}/kafka/ca.crt" && \
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.ca\.crt}' | base64 -d >> "${SECRETS_DIR}/kafka/ca.crt" && \
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.user\.p12}' | base64 -d > "${SECRETS_DIR}/kafka/user.p12"
}

# Function create an spring boot application yaml
GENERATE_SPRING_BOOT() {
  cat - <<YAML > "${REPO_ROOT}/application.yaml"
spring:
  kafka:
    bootstrap-servers: bootstrap.${PROJECT_DOMAIN}:9094
    security:
      protocol: SSL
    ssl:
      key-store-type: PKCS12
      key-store-location: file://${SECRETS_DIR}/kafka/user.p12
      key-store-password: $(cat "${SECRETS_DIR}/kafka/userpass.txt")
      trust-store-type: PEM
      trust-store-location: file://${SECRETS_DIR}/kafka/ca.crt
    properties:
      auto.register.schemas: true
      schema.registry.url: https://sr.${PROJECT_DOMAIN}
      ssl.client.auth: true
YAML

  echo Ensure that the following environment variable is defined SPRING_CONFIG_ADDITIONAL_LOCATION=file://${REPO_ROOT}/application.yaml
}

# Check command line arguments to determine which function to call
if [ "${1:-}" = "deps" ]; then
    KIND_UPDATE_DEPENDENCIES
elif [ "${1:-}" = "create-cluster" ]; then
    KIND_CREATE_CLUSTER
elif [ "${1:-}" = "get-secrets" ]; then
    KIND_GET_SECRETS
    GENERATE_SPRING_BOOT
elif [ "${1:-}" = "delete-cluster" ]; then
    KIND_DELETE_CLUSTER
elif [ "${1:-}" = "recreate-cluster" ]; then
    KIND_DELETE_CLUSTER
    KIND_CREATE_CLUSTER
    KIND_GET_SECRETS
    GENERATE_SPRING_BOOT
else
    echo "Usage: $0 {deps|create-cluster|get-secrets|delete-cluster|recreate-cluster}"
    exit 1
fi
