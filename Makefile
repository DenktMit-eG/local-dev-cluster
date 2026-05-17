PROJECT_DOMAIN ?= local.lgc

DEPENDENCY_CHARTS := \
	cert-manager \
	traefik \
	strimzi-kafka-operator \
	strimzi-registry-operator

TEMPLATE_RELEASES := \
	cert-manager:cert-manager \
	traefik:traefik \
	strimzi-kafka-operator:strimzi-kafka-operator \
	strimzi-registry-operator:strimzi-registry-operator \
	glue:dev-glue \
	keycloak:keycloak

.PHONY: help deps kind-create-local kind-recreate-local secrets lint template validate validate-cluster debug-cluster clean clean-secrets

help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "%-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Refresh Helm dependencies for wrapper charts.
	./scripts/kind_setup.sh deps

kind-create-local: ## Create the local kind cluster, install charts, and export Kafka secrets.
	./scripts/kind_setup.sh create-cluster
	./scripts/kind_setup.sh get-secrets

kind-recreate-local: ## Delete and recreate the local kind cluster.
	./scripts/kind_setup.sh delete-cluster
	./scripts/kind_setup.sh create-cluster
	./scripts/kind_setup.sh get-secrets

secrets: ## Export Kafka client secrets and regenerate application.yaml.
	./scripts/kind_setup.sh get-secrets

lint: ## Run helm lint for every chart.
	@set -e; \
	for chart in $(DEPENDENCY_CHARTS) dev-glue keycloak; do \
		echo "==> helm lint charts/$$chart"; \
		helm lint "charts/$$chart"; \
	done

template: ## Render every chart with the local project domain.
	@set -e; \
	for item in $(TEMPLATE_RELEASES); do \
		release=$${item%%:*}; \
		chart=$${item##*:}; \
		echo "==> helm template $$release charts/$$chart"; \
		helm template "$$release" "charts/$$chart" --set "global.projectDomain=$(PROJECT_DOMAIN)" >/dev/null; \
	done

validate: lint template ## Run local chart validation checks.

validate-cluster: ## Run end-to-end health checks against the running cluster.
	./scripts/validate-cluster.sh

debug-cluster: ## Dump cluster state to scripts/debug/<timestamp>/ for troubleshooting.
	./scripts/debug-cluster.sh

clean-secrets: ## Remove generated Kafka client secrets and application.yaml.
	rm -rf $(CURDIR)/secrets $(CURDIR)/application.yaml

clean: clean-secrets ## Delete the local kind cluster and remove generated secrets.
	./scripts/kind_setup.sh delete-cluster
