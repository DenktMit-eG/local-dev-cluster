#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
SECRETS_DIR="${REPO_ROOT}/secrets"

# Cluster identity. Override any of these via env if you forked the harness.
PROJECT_DOMAIN="${PROJECT_DOMAIN:-local.lgc}"
KUBE_CONTEXT="${KUBE_CONTEXT:-kind-lgc}"
GLUE_NAMESPACE="${GLUE_NAMESPACE:-glue}"
GLUE_RELEASE="${GLUE_RELEASE:-glue}"
KAFKA_CLUSTER="${KAFKA_CLUSTER:-kafka-lfg}"
KAFKA_NODEPOOL="${KAFKA_NODEPOOL:-${KAFKA_CLUSTER}-default}"
KAFKA_CERT="${KAFKA_CERT:-${GLUE_RELEASE}-broker}"
KAFKA_CERT_SECRET="${KAFKA_CERT_SECRET:-kafka-broker-ca}"
SR_DEPLOY="${SR_DEPLOY:-confluent-schema-registry}"

if [ -t 1 ]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; YELLOW=""; BOLD=""; RESET=""
fi

PASS=0
FAIL=0
SKIP=0

PASSED() { printf "  ${GREEN}PASS${RESET}  %s\n" "$1"; PASS=$((PASS+1)); }
FAILED() { printf "  ${RED}FAIL${RESET}  %s\n" "$1"; FAIL=$((FAIL+1)); }
SKIPPED() { printf "  ${YELLOW}SKIP${RESET}  %s\n" "$1"; SKIP=$((SKIP+1)); }
SECTION() { printf "\n${BOLD}== %s ==${RESET}\n" "$1"; }

NEED() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf "${RED}error:${RESET} required tool '%s' not installed\n" "$1" >&2
    exit 2
  fi
}

NEED kubectl

# 1. Prereqs ----------------------------------------------------------------
SECTION "Prerequisites"
if [ "$(kubectl config current-context 2>/dev/null)" = "${KUBE_CONTEXT}" ]; then
  PASSED "kubectl context is ${KUBE_CONTEXT}"
else
  FAILED "kubectl context is not ${KUBE_CONTEXT} ($(kubectl config current-context 2>/dev/null || echo none))"
fi

for host in bootstrap b0 sr keycloak; do
  fqdn="${host}.${PROJECT_DOMAIN}"
  if getent hosts "${fqdn}" 2>/dev/null | grep -qE '^127\.0\.0\.1\b'; then
    PASSED "/etc/hosts: ${fqdn} -> 127.0.0.1"
  else
    FAILED "/etc/hosts is missing 127.0.0.1 ${fqdn}"
  fi
done

# 2. Operator pods ----------------------------------------------------------
SECTION "Operator pods"
CHECK_DEPLOY() {
  local ns="$1" deploy="$2"
  local ready
  ready=$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo "")
  if [ "${ready}" = "1/1" ] || [ "${ready%/*}" = "${ready#*/}" ] && [ -n "${ready%/*}" ]; then
    PASSED "${ns}/${deploy} ready (${ready})"
  else
    FAILED "${ns}/${deploy} not ready (${ready:-missing})"
  fi
}

CHECK_DEPLOY cert-manager           cert-manager
CHECK_DEPLOY cert-manager           cert-manager-webhook
CHECK_DEPLOY cert-manager           cert-manager-cainjector
CHECK_DEPLOY traefik                traefik
CHECK_DEPLOY strimzi-kafka-operator strimzi-cluster-operator
CHECK_DEPLOY strimzi-kafka-operator strimzi-registry-operator
CHECK_DEPLOY keycloak               keycloak

# 3. Strimzi CRs in the glue namespace --------------------------------------
SECTION "Strimzi CRs"
CHECK_CR_READY() {
  local ns="$1" kind="$2" name="$3"
  local ready
  ready=$(kubectl -n "${ns}" get "${kind}" "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "${ready}" = "True" ]; then
    PASSED "${kind}/${name} Ready=True"
  else
    FAILED "${kind}/${name} Ready=${ready:-missing}"
  fi
}

CHECK_CR_READY "${GLUE_NAMESPACE}" kafka      "${KAFKA_CLUSTER}"
CHECK_CR_READY "${GLUE_NAMESPACE}" kafkauser  kafka-super-user
CHECK_CR_READY "${GLUE_NAMESPACE}" kafkauser  confluent-schema-registry
CHECK_CR_READY "${GLUE_NAMESPACE}" kafkatopic registry-schemas

# KafkaNodePool has no Ready condition; verify status.nodeIds was populated.
np_replicas=$(kubectl -n "${GLUE_NAMESPACE}" get kafkanodepool "${KAFKA_NODEPOOL}" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "")
np_nodeids=$(kubectl -n "${GLUE_NAMESPACE}" get kafkanodepool "${KAFKA_NODEPOOL}" -o jsonpath='{.status.nodeIds}' 2>/dev/null || echo "")
if [ -n "${np_replicas}" ] && [ "${np_replicas}" != "0" ] && [ -n "${np_nodeids}" ]; then
  PASSED "KafkaNodePool ${KAFKA_NODEPOOL} replicas=${np_replicas} nodeIds=${np_nodeids}"
else
  FAILED "KafkaNodePool ${KAFKA_NODEPOOL} has no replicas/nodeIds in status"
fi

# Strimzi 0.51 dropped status.kafkaMetadataState since KRaft is the only supported mode.
# Verify the broker actually came up by checking status.kafkaVersion is populated.
kafka_version=$(kubectl -n "${GLUE_NAMESPACE}" get kafka "${KAFKA_CLUSTER}" -o jsonpath='{.status.kafkaVersion}' 2>/dev/null || echo "")
if [ -n "${kafka_version}" ]; then
  PASSED "Kafka ${KAFKA_CLUSTER} status.kafkaVersion=${kafka_version}"
else
  FAILED "Kafka ${KAFKA_CLUSTER} has no status.kafkaVersion (broker did not finish startup)"
fi

# StrimziSchemaRegistry has no status.conditions; the operator creates a Deployment
# whose name matches the CR name. Match by name first, then fall back to any deployment
# in the namespace whose name contains "schema-registry".
sr_deploy=$(kubectl -n "${GLUE_NAMESPACE}" get deploy "${SR_DEPLOY}" -o name 2>/dev/null \
  || kubectl -n "${GLUE_NAMESPACE}" get deploy -o name 2>/dev/null | grep -i schema-registry | head -1)
if [ -n "${sr_deploy}" ]; then
  sr_ready=$(kubectl -n "${GLUE_NAMESPACE}" get "${sr_deploy}" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo "")
  if [ "${sr_ready}" = "1/1" ]; then
    PASSED "StrimziSchemaRegistry deployment ready (${sr_ready})"
  else
    FAILED "StrimziSchemaRegistry deployment ${sr_deploy} not ready (${sr_ready:-missing})"
  fi
else
  FAILED "StrimziSchemaRegistry deployment not found (operator did not reconcile the CR)"
fi

# 4. Cert-manager + TLS plumbing --------------------------------------------
SECTION "TLS plumbing"
if kubectl get clusterissuer default-cluster-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
  PASSED "ClusterIssuer default-cluster-issuer Ready=True"
else
  FAILED "ClusterIssuer default-cluster-issuer not Ready"
fi

if kubectl -n "${GLUE_NAMESPACE}" get certificate "${KAFKA_CERT}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
  PASSED "Certificate ${GLUE_NAMESPACE}/${KAFKA_CERT} Ready=True"
else
  FAILED "Certificate ${GLUE_NAMESPACE}/${KAFKA_CERT} not Ready"
fi

if kubectl -n "${GLUE_NAMESPACE}" get secret "${KAFKA_CERT_SECRET}" -o jsonpath='{.type}' 2>/dev/null | grep -q kubernetes.io/tls; then
  PASSED "Secret ${GLUE_NAMESPACE}/${KAFKA_CERT_SECRET} exists and is TLS-typed"
else
  FAILED "Secret ${GLUE_NAMESPACE}/${KAFKA_CERT_SECRET} missing or wrong type"
fi

# 5. HTTPS endpoints via Traefik --------------------------------------------
SECTION "HTTPS endpoints"
CHECK_HTTP() {
  local url="$1" expect="$2"
  local code ok=0
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "${url}" 2>/dev/null || echo "000")
  case "${expect}" in
    2xx)
      if [ "${code:0:1}" = "2" ]; then ok=1; fi
      ;;
    any2or3xx)
      if [ "${code:0:1}" = "2" ] || [ "${code:0:1}" = "3" ]; then ok=1; fi
      ;;
    *)
      if [ "${code}" = "${expect}" ]; then ok=1; fi
      ;;
  esac
  if [ "${ok}" = "1" ]; then
    PASSED "${url} -> ${code}"
  else
    FAILED "${url} -> ${code} (expected ${expect})"
  fi
}

CHECK_HTTP "https://keycloak.${PROJECT_DOMAIN}/"            any2or3xx
CHECK_HTTP "https://keycloak.${PROJECT_DOMAIN}/realms/sandbox/.well-known/openid-configuration" 200
CHECK_HTTP "https://sr.${PROJECT_DOMAIN}/subjects"          200

# 6. Local Kafka client secrets --------------------------------------------
SECTION "Kafka client secrets on disk"
for f in "${SECRETS_DIR}/kafka/user.p12" "${SECRETS_DIR}/kafka/userpass.txt" "${SECRETS_DIR}/kafka/ca.crt"; do
  if [ -s "${f}" ]; then
    PASSED "$(basename "${f}") present and non-empty"
  else
    FAILED "${f} missing or empty (run: make secrets)"
  fi
done

# 7. End-to-end Kafka mTLS via Traefik -------------------------------------
SECTION "Kafka mTLS via Traefik (port 9094)"
if command -v kcat >/dev/null 2>&1; then
  KCAT=kcat
elif command -v kafkacat >/dev/null 2>&1; then
  KCAT=kafkacat
else
  KCAT=""
fi

if [ -z "${KCAT}" ]; then
  SKIPPED "kcat / kafkacat not installed; install with: apt install kafkacat (or brew install kcat)"
elif [ ! -s "${SECRETS_DIR}/kafka/userpass.txt" ]; then
  SKIPPED "secrets/kafka/userpass.txt missing; cannot exercise mTLS"
else
  KCAT_OPTS=(
    -X security.protocol=SSL
    -X ssl.ca.location="${SECRETS_DIR}/kafka/ca.crt"
    -X ssl.keystore.location="${SECRETS_DIR}/kafka/user.p12"
    -X ssl.keystore.password="$(cat "${SECRETS_DIR}/kafka/userpass.txt")"
  )

  if "${KCAT}" -b "bootstrap.${PROJECT_DOMAIN}:9094" -L "${KCAT_OPTS[@]}" 2>/dev/null | grep -q '1 brokers'; then
    PASSED "kcat -L lists 1 broker via bootstrap.${PROJECT_DOMAIN}:9094"
  else
    FAILED "kcat -L failed against bootstrap.${PROJECT_DOMAIN}:9094"
  fi

  topic="validate-cluster-$(date +%s)"
  if echo "ping-$$" | "${KCAT}" -b "bootstrap.${PROJECT_DOMAIN}:9094" -t "${topic}" -P "${KCAT_OPTS[@]}" 2>/dev/null; then
    msg=$("${KCAT}" -b "bootstrap.${PROJECT_DOMAIN}:9094" -t "${topic}" -C -e -q "${KCAT_OPTS[@]}" 2>/dev/null | head -1)
    if [ "${msg}" = "ping-$$" ]; then
      PASSED "produce+consume round-trip on topic ${topic}"
    else
      FAILED "produce+consume returned '${msg:-<empty>}', expected ping-$$"
    fi
  else
    FAILED "produce to topic ${topic} failed"
  fi
fi

# 8. Schema Registry round-trip --------------------------------------------
SECTION "Schema Registry"
subjects=$(curl -sk --max-time 5 "https://sr.${PROJECT_DOMAIN}/subjects" 2>/dev/null || echo "")
if [ "${subjects}" = "[]" ] || echo "${subjects}" | grep -q '^\['; then
  PASSED "Schema Registry /subjects returns JSON array: ${subjects}"
else
  FAILED "Schema Registry /subjects returned: ${subjects:-<empty>}"
fi

# Summary -------------------------------------------------------------------
SECTION "Summary"
printf "  %s%d passed%s   %s%d failed%s   %s%d skipped%s\n" \
  "${GREEN}" "${PASS}" "${RESET}" "${RED}" "${FAIL}" "${RESET}" "${YELLOW}" "${SKIP}" "${RESET}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
