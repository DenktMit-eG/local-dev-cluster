#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
mkdir -p "${SCRIPT_DIR}/../secrets"
SECRETS_DIR="$( cd "${SCRIPT_DIR}/../secrets" &> /dev/null && pwd )"

# Function to create kind cluster and setup helm charts
KIND_CREATE_CLUSTER() {
    CHECK_PREREQUISITES
    kind create cluster --config=./kind/kind-cluster.yaml && \
    helm dep up charts/strimzi-kafka-operator && \
    helm dep up charts/strimzi-registry-operator && \
    helm dep up charts/traefik && \
    helm dep up charts/cert-manager && \
    export PROJECT_DOMAIN="local.lgc" && \
    helm upgrade --install --create-namespace --namespace cert-manager cert-manager charts/cert-manager --atomic && \
    helm upgrade --install --create-namespace --namespace traefik traefik charts/traefik --atomic && \
    helm upgrade --install --create-namespace --namespace strimzi-kafka-operator strimzi-kafka-operator charts/strimzi-kafka-operator --atomic && \
    kubectl create secret tls root-ca-secret \
      --cert="$(mkcert -CAROOT)/rootCA.pem" \
      --key="$(mkcert -CAROOT)/rootCA-key.pem" \
      --namespace=cert-manager && \
    helm upgrade --install -n strimzi-kafka-operator  strimzi-registry-operator charts/strimzi-registry-operator
    helm upgrade --create-namespace --install -n glue glue ./charts/dev-glue --atomic  --set "global.projectDomain=${PROJECT_DOMAIN}" && \
    helm upgrade --install --create-namespace --atomic --namespace keycloak keycloak ./charts/keycloak --set "global.projectDomain=${PROJECT_DOMAIN}"
}

# Function to retrieve secrets for Kafka
KIND_GET_SECRETS() {
    CHECK_PREREQUISITES
    mkdir -p "${SECRETS_DIR}/kafka"
    sleep 15 # Workaround: waiting for https://github.com/kubernetes/kubernetes/pull/122994 to get merged
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.user\.password}' | base64 -d > "${SECRETS_DIR}/kafka/userpass.txt" && \
    cat "$(mkcert -CAROOT)/rootCA.pem" > "${SECRETS_DIR}/kafka/ca.crt" && \
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.ca\.crt}' | base64 -d >> "${SECRETS_DIR}/kafka/ca.crt" && \
    kubectl -n glue get secrets kafka-super-user -o jsonpath='{.data.user\.p12}' | base64 -d > "${SECRETS_DIR}/kafka/user.p12"
}

# Function create an spring boot application yaml
GENERATE_SPRING_BOOT() {
  cat - <<YAML > "${SCRIPT_DIR}/../application.yaml"
spring:
  kafka:
    bootstrap-servers: bootstrap.local.lgc:9094
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
      schema.registry.url: https://sr.local.lgc
      ssl.client.auth: true
YAML

  echo Ensure that the following environment variable is defined SPRING_CONFIG_ADDITIONAL_LOCATION=file://${PWD}/application.yaml
}

CHECK_PREREQUISITES() {
  if ! hash kubectl 2>/dev/null; then fail "kubectl not installed"; exit 1; fi
  if ! hash helm 2>/dev/null; then fail "helm not installed"; exit 1; fi
  if ! hash mkcert 2>/dev/null; then fail "mkcert not installed"; exit 1; fi
  if ! hash Docker 2>/dev/null; then fail "Docker not installed"; exit 1; fi
}

# Check command line arguments to determine which function to call
if [ "$1" = "create-cluster" ]; then
    KIND_CREATE_CLUSTER
elif [ "$1" = "get-secrets" ]; then
    KIND_GET_SECRETS
    GENERATE_SPRING_BOOT
else
    echo "Usage: $0 {create-cluster|get-secrets}"
    exit 1
fi
