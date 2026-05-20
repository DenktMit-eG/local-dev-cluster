#!/usr/bin/env bash
# Dump every piece of state useful for debugging the local-dev kind cluster
# into scripts/debug/<timestamp>/. Each file is named after what it contains
# so a reader can find what they need without grepping the whole bundle.
#
# Secret contents are never written; only secret names. mkcert/Kafka client
# keys live under secrets/ and are out of scope here.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_ROOT="${REPO_ROOT}/scripts/debug/${TS}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "error: kubectl not installed" >&2
  exit 2
fi

mkdir -p \
  "${OUT_ROOT}/cluster" \
  "${OUT_ROOT}/tls" \
  "${OUT_ROOT}/ns-cert-manager" \
  "${OUT_ROOT}/ns-traefik" \
  "${OUT_ROOT}/ns-strimzi-kafka-operator" \
  "${OUT_ROOT}/ns-glue" \
  "${OUT_ROOT}/ns-keycloak" \
  "${OUT_ROOT}/charts"

RUN() {
  # RUN <output-file> <kubectl args...>
  # Writes the command itself as the first line and the output (or error) below.
  local out="$1"; shift
  {
    printf "$ kubectl %s\n" "$*"
    kubectl "$@" 2>&1
    printf "\n[exit=%d]\n" "${PIPESTATUS[0]}"
  } > "${out}"
}

LOGS() {
  # LOGS <output-file> <namespace> <selector-flag-and-value...>
  # Tries current container logs first; if container has restarted, also grabs --previous.
  local out="$1" ns="$2"; shift 2
  {
    printf "$ kubectl -n %s logs %s --tail=500\n" "${ns}" "$*"
    kubectl -n "${ns}" logs "$@" --tail=500 2>&1
    printf "\n[exit=%d]\n" "${PIPESTATUS[0]}"
    printf "\n--- previous container (if any) ---\n"
    printf "$ kubectl -n %s logs %s --previous --tail=500\n" "${ns}" "$*"
    kubectl -n "${ns}" logs "$@" --previous --tail=500 2>&1 || true
  } > "${out}"
}

echo "Writing debug bundle to ${OUT_ROOT}"
echo

# 0. Bundle manifest --------------------------------------------------------
{
  echo "Debug bundle for local-dev-cluster"
  echo "Collected: ${TS}"
  echo "Host:      $(uname -a)"
  echo "Context:   $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "Repo:      ${REPO_ROOT}"
  echo
  echo "Directory layout:"
  echo "  00-validate.txt            output of scripts/validate-cluster.sh (read first)"
  echo "  cluster/                   nodes, all pods, events, helm releases, CRD list"
  echo "  tls/                       cert-manager Issuers, Certificates, CertificateRequests, Orders"
  echo "  ns-cert-manager/           cert-manager controller + webhook + cainjector"
  echo "  ns-traefik/                Traefik controller + IngressRoute(TCP) configs"
  echo "  ns-strimzi-kafka-operator/ Strimzi cluster operator + registry operator"
  echo "  ns-glue/                   Kafka cluster, KafkaNodePool, users, topics, schema-registry, kafka-ui (+ kafka-ui-api.txt for the UI's own cluster view)"
  echo "  ns-keycloak/               Keycloak deployment + realm import ConfigMap"
  echo "  charts/                    Wrapper Chart.yaml + values overlays for reference"
} > "${OUT_ROOT}/00-bundle-manifest.txt"

# 0b. Validate ---------------------------------------------------------------
# Run the validator first so its pass/fail summary sits at the top of the
# bundle. Strip ANSI escape codes so the file is grep-friendly; preserve the
# script's exit code on the last line for easy diffing across bundles.
VALIDATE="${SCRIPT_DIR}/validate-cluster.sh"
if [ -x "${VALIDATE}" ]; then
  {
    printf "$ %s\n\n" "${VALIDATE}"
    NO_COLOR=1 "${VALIDATE}" 2>&1 | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'
    printf "\n[exit=%d]\n" "${PIPESTATUS[0]}"
  } > "${OUT_ROOT}/00-validate.txt"
else
  echo "validate-cluster.sh not found or not executable at ${VALIDATE}" > "${OUT_ROOT}/00-validate.txt"
fi

# 1. Cluster-wide ----------------------------------------------------------
RUN "${OUT_ROOT}/cluster/kubectl-version.txt"  version
RUN "${OUT_ROOT}/cluster/nodes.yaml"           get nodes -o yaml
RUN "${OUT_ROOT}/cluster/nodes.txt"            get nodes -o wide
RUN "${OUT_ROOT}/cluster/all-pods.txt"         get pods -A -o wide
RUN "${OUT_ROOT}/cluster/all-events.txt"       get events -A --sort-by=.lastTimestamp
RUN "${OUT_ROOT}/cluster/all-namespaces.txt"   get namespaces
RUN "${OUT_ROOT}/cluster/crds.txt"             get crd
RUN "${OUT_ROOT}/cluster/api-resources.txt"    api-resources --verbs=list --namespaced -o wide

if command -v helm >/dev/null 2>&1; then
  {
    echo "$ helm ls -A"
    helm ls -A 2>&1
  } > "${OUT_ROOT}/cluster/helm-releases.txt"
fi

# 2. cert-manager ----------------------------------------------------------
RUN "${OUT_ROOT}/ns-cert-manager/pods.txt"     -n cert-manager get pods -o wide
RUN "${OUT_ROOT}/ns-cert-manager/deploy.yaml"  -n cert-manager get deploy -o yaml
RUN "${OUT_ROOT}/ns-cert-manager/svc.txt"      -n cert-manager get svc -o wide
RUN "${OUT_ROOT}/ns-cert-manager/events.txt"   -n cert-manager get events --sort-by=.lastTimestamp
RUN "${OUT_ROOT}/ns-cert-manager/secrets-names.txt" -n cert-manager get secret -o name
LOGS "${OUT_ROOT}/ns-cert-manager/logs-cert-manager.log"             cert-manager deploy/cert-manager
LOGS "${OUT_ROOT}/ns-cert-manager/logs-cert-manager-webhook.log"     cert-manager deploy/cert-manager-webhook
LOGS "${OUT_ROOT}/ns-cert-manager/logs-cert-manager-cainjector.log"  cert-manager deploy/cert-manager-cainjector

# 3. TLS resources cluster-wide -------------------------------------------
RUN "${OUT_ROOT}/tls/clusterissuers.yaml"          get clusterissuers -o yaml
RUN "${OUT_ROOT}/tls/certificates-all.txt"         get certificate -A -o wide
RUN "${OUT_ROOT}/tls/certificates-glue.yaml"       -n glue get certificate -o yaml
RUN "${OUT_ROOT}/tls/certificaterequests-glue.yaml" -n glue get certificaterequest -o yaml
RUN "${OUT_ROOT}/tls/orders-glue.yaml"             -n glue get order -o yaml
RUN "${OUT_ROOT}/tls/challenges-glue.yaml"         -n glue get challenge -o yaml

# 4. Traefik ---------------------------------------------------------------
RUN "${OUT_ROOT}/ns-traefik/pods.txt"          -n traefik get pods -o wide
RUN "${OUT_ROOT}/ns-traefik/deploy.yaml"       -n traefik get deploy -o yaml
RUN "${OUT_ROOT}/ns-traefik/svc.txt"           -n traefik get svc -o wide
RUN "${OUT_ROOT}/ns-traefik/events.txt"        -n traefik get events --sort-by=.lastTimestamp
RUN "${OUT_ROOT}/ns-traefik/configmap.yaml"    -n traefik get configmap -o yaml
LOGS "${OUT_ROOT}/ns-traefik/logs-traefik.log" traefik deploy/traefik

# Traefik CRDs cluster-wide (the routing config could be in any ns)
RUN "${OUT_ROOT}/ns-traefik/ingressroutes-all.yaml"    get ingressroute -A -o yaml
RUN "${OUT_ROOT}/ns-traefik/ingressroutetcps-all.yaml" get ingressroutetcp -A -o yaml
RUN "${OUT_ROOT}/ns-traefik/middlewares-all.yaml"      get middleware -A -o yaml
RUN "${OUT_ROOT}/ns-traefik/ingresses-all.yaml"        get ingress -A -o yaml

# 5. Strimzi operators -----------------------------------------------------
RUN "${OUT_ROOT}/ns-strimzi-kafka-operator/pods.txt"    -n strimzi-kafka-operator get pods -o wide
RUN "${OUT_ROOT}/ns-strimzi-kafka-operator/pods.yaml"   -n strimzi-kafka-operator get pods -o yaml
RUN "${OUT_ROOT}/ns-strimzi-kafka-operator/deploy.yaml" -n strimzi-kafka-operator get deploy -o yaml
RUN "${OUT_ROOT}/ns-strimzi-kafka-operator/events.txt"  -n strimzi-kafka-operator get events --sort-by=.lastTimestamp
LOGS "${OUT_ROOT}/ns-strimzi-kafka-operator/logs-strimzi-cluster-operator.log"  strimzi-kafka-operator deploy/strimzi-cluster-operator
LOGS "${OUT_ROOT}/ns-strimzi-kafka-operator/logs-strimzi-registry-operator.log" strimzi-kafka-operator deploy/strimzi-registry-operator

# 6. glue namespace (the actual application stack) -------------------------
RUN "${OUT_ROOT}/ns-glue/pods.txt"             -n glue get pods -o wide
RUN "${OUT_ROOT}/ns-glue/pods.yaml"            -n glue get pods -o yaml
RUN "${OUT_ROOT}/ns-glue/svc.txt"              -n glue get svc -o wide
RUN "${OUT_ROOT}/ns-glue/all.txt"              -n glue get all -o wide
RUN "${OUT_ROOT}/ns-glue/events.txt"           -n glue get events --sort-by=.lastTimestamp
RUN "${OUT_ROOT}/ns-glue/deploy.yaml"          -n glue get deploy -o yaml
RUN "${OUT_ROOT}/ns-glue/statefulset.yaml"     -n glue get statefulset -o yaml
RUN "${OUT_ROOT}/ns-glue/strimzipodsets.yaml"  -n glue get strimzipodset -o yaml
RUN "${OUT_ROOT}/ns-glue/pvc.txt"              -n glue get pvc -o wide
RUN "${OUT_ROOT}/ns-glue/secrets-names.txt"    -n glue get secret -o name
RUN "${OUT_ROOT}/ns-glue/configmaps.yaml"      -n glue get configmap -o yaml
RUN "${OUT_ROOT}/ns-glue/ingresses.yaml"       -n glue get ingress -o yaml
RUN "${OUT_ROOT}/ns-glue/ingressroutetcp.yaml" -n glue get ingressroutetcp -o yaml

# Strimzi CRs (per kind, full yaml so status is visible)
RUN "${OUT_ROOT}/ns-glue/kafka.yaml"                 -n glue get kafka -o yaml
RUN "${OUT_ROOT}/ns-glue/kafkanodepool.yaml"         -n glue get kafkanodepool -o yaml
RUN "${OUT_ROOT}/ns-glue/kafkauser.yaml"             -n glue get kafkauser -o yaml
RUN "${OUT_ROOT}/ns-glue/kafkatopic.yaml"            -n glue get kafkatopic -o yaml
RUN "${OUT_ROOT}/ns-glue/strimzischemaregistry.yaml" -n glue get strimzischemaregistry -o yaml

# describe gives human-readable event tail per resource (often more useful than the yaml status block)
RUN "${OUT_ROOT}/ns-glue/describe-strimzischemaregistry.txt" -n glue describe strimzischemaregistry
RUN "${OUT_ROOT}/ns-glue/describe-kafka.txt"                 -n glue describe kafka
RUN "${OUT_ROOT}/ns-glue/describe-kafkanodepool.txt"         -n glue describe kafkanodepool

# Pod logs for everything in glue. Iterate pods to get a per-pod file even when the
# pod doesn't belong to a Deployment (StrimziPodSet pods, for example).
for pod in $(kubectl -n glue get pods -o name 2>/dev/null); do
  name="${pod#pod/}"
  LOGS "${OUT_ROOT}/ns-glue/logs-${name}.log" glue "${pod}" --all-containers=true
done

# 6b. Kafka UI external API snapshot ---------------------------------------
# Kafka UI's /api/clusters returns its own view of the broker connection. When
# the UI runs but cannot reach Kafka over mTLS, the deployment is Ready but the
# cluster shows "status":"offline" with a "lastKafkaException" field. Capturing
# this here saves a manual curl during triage.
KAFKA_UI_HOST="kafka-ui.${PROJECT_DOMAIN:-local.lgc}"
{
  printf "$ curl -sk https://%s/api/clusters\n" "${KAFKA_UI_HOST}"
  curl -sk --max-time 5 "https://${KAFKA_UI_HOST}/api/clusters" 2>&1 || true
  printf "\n\n$ curl -sk https://%s/actuator/health\n" "${KAFKA_UI_HOST}"
  curl -sk --max-time 5 "https://${KAFKA_UI_HOST}/actuator/health" 2>&1 || true
} > "${OUT_ROOT}/ns-glue/kafka-ui-api.txt"

# 7. Keycloak --------------------------------------------------------------
RUN "${OUT_ROOT}/ns-keycloak/pods.txt"      -n keycloak get pods -o wide
RUN "${OUT_ROOT}/ns-keycloak/deploy.yaml"   -n keycloak get deploy -o yaml
RUN "${OUT_ROOT}/ns-keycloak/svc.txt"       -n keycloak get svc -o wide
RUN "${OUT_ROOT}/ns-keycloak/events.txt"    -n keycloak get events --sort-by=.lastTimestamp
RUN "${OUT_ROOT}/ns-keycloak/configmap.yaml" -n keycloak get configmap -o yaml
RUN "${OUT_ROOT}/ns-keycloak/ingresses.yaml" -n keycloak get ingress -o yaml
LOGS "${OUT_ROOT}/ns-keycloak/logs-keycloak.log" keycloak deploy/keycloak

# 8. Chart sources for reference (so a reader doesn't need the repo) -------
for f in \
  "charts/cert-manager/Chart.yaml" \
  "charts/cert-manager/values.yaml" \
  "charts/traefik/Chart.yaml" \
  "charts/traefik/values.yaml" \
  "charts/strimzi-kafka-operator/Chart.yaml" \
  "charts/strimzi-kafka-operator/values.yaml" \
  "charts/strimzi-registry-operator/Chart.yaml" \
  "charts/strimzi-registry-operator/values.yaml" \
  "charts/keycloak/Chart.yaml" \
  "charts/keycloak/values.yaml" \
  "charts/dev-glue/Chart.yaml" \
  "charts/dev-glue/values.yaml" \
  "kind/kind-cluster.yaml"; do
  src="${REPO_ROOT}/${f}"
  if [ -f "${src}" ]; then
    dest="${OUT_ROOT}/charts/$(echo "${f}" | tr '/' '_')"
    cp "${src}" "${dest}"
  fi
done

# 9. Bundle stats + tar -----------------------------------------------------
files=$(find "${OUT_ROOT}" -type f | wc -l)
bytes=$(du -sb "${OUT_ROOT}" 2>/dev/null | awk '{print $1}')
tarball="${OUT_ROOT}.tar.gz"
tar -czf "${tarball}" -C "$(dirname "${OUT_ROOT}")" "$(basename "${OUT_ROOT}")"

echo
echo "Wrote ${files} files (${bytes:-?} bytes) to:"
echo "  ${OUT_ROOT}"
echo "Tarball:"
echo "  ${tarball}"
echo
echo "Quick look at the things most likely to fail:"
echo "  cat ${OUT_ROOT}/00-validate.txt"
echo "  cat ${OUT_ROOT}/ns-strimzi-kafka-operator/logs-strimzi-registry-operator.log"
echo "  cat ${OUT_ROOT}/ns-glue/describe-strimzischemaregistry.txt"
echo "  cat ${OUT_ROOT}/ns-glue/events.txt"
