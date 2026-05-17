# Local Dev Cluster

A single-machine Kubernetes cluster for working against Kafka, Schema Registry, and Keycloak with real TLS. The cluster
runs in Docker via [kind](https://kind.sigs.k8s.io/), exposes services on `*.local.lgc`, and is brought up by one
script.

It is meant for integration testing and local application work, not production.

## What is included

| Area               | Implementation                                                    |
|--------------------|-------------------------------------------------------------------|
| Kubernetes runtime | kind cluster `lgc` (1 control-plane, 3 workers, pinned `kindest/node:v1.31.14`) |
| Ingress            | Traefik 40.2.0, pinned to the control-plane node                  |
| TLS                | cert-manager v1.20.2, issuing from the local mkcert root CA       |
| Kafka              | Strimzi Operator 0.46.1, Kafka 3.9.0 with KRaft, single broker    |
| Schema Registry    | Confluent Schema Registry 7.9.6 via the Strimzi Registry Operator |
| Identity           | Keycloak 26.6.1 with a `sandbox` realm imported on start          |

## Where to start

If you are setting the cluster up on your machine for the first time, follow the Getting Started section in order:

1. [Prerequisites](getting-started/prerequisites.md)
2. [Local Setup](getting-started/local-setup.md)
3. [Accessing Services](getting-started/accessing-services.md)

If you want to use the running cluster from an application:

- [Kafka and Schema Registry](developer-guide/kafka-and-schema-registry.md) for client configuration
- [Keycloak Sandbox](developer-guide/keycloak-sandbox.md) for OIDC integration
- [Spring Boot Configuration](developer-guide/spring-boot-configuration.md) if you are wiring `spring-kafka`

If you are diagnosing a problem or rebuilding the cluster:

- [Troubleshooting](operations/troubleshooting.md)
- [Recreate Cluster](operations/recreate-cluster.md)

## Previewing this documentation

From the `_backstage/` directory:

```bash
docker compose up
```

Open `http://localhost:8000/`. Stop with Ctrl+C.
