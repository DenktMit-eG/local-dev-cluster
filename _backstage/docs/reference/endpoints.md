# Endpoints

All endpoints assume `global.projectDomain` is the default `local.lgc` and that the four hostnames are mapped to
`127.0.0.1` in `/etc/hosts` (see [Accessing Services](../getting-started/accessing-services.md)).

## External

| Hostname              | Port | Protocol   | Auth                                                    | Backed by                                                           |
|-----------------------|------|------------|---------------------------------------------------------|---------------------------------------------------------------------|
| `keycloak.local.lgc`  | 443  | HTTPS      | Realm `sandbox` (`admin`/`admin` for the admin console) | `Ingress keycloak` in ns `keycloak`                                 |
| `sr.local.lgc`        | 443  | HTTPS      | None on the registry itself                             | `Ingress schema-registry` in ns `glue`                              |
| `bootstrap.local.lgc` | 9094 | TLS (mTLS) | Client cert from `secrets/kafka/user.p12`               | `IngressRouteTCP` SNI route to `kafka-lfg-kafka-external-bootstrap` |
| `b0.local.lgc`        | 9094 | TLS (mTLS) | Client cert from `secrets/kafka/user.p12`               | `IngressRouteTCP` SNI route to `kafka-lfg-kafka-lfg-default-0`      |

## In-cluster

| Service                         | DNS                                  | Port | Notes                                                                           |
|---------------------------------|--------------------------------------|------|---------------------------------------------------------------------------------|
| Kafka bootstrap, internal mTLS  | `kafka-lfg-kafka-bootstrap.glue.svc` | 9093 | Used by the Schema Registry; available to any in-cluster app with a `KafkaUser` |
| Kafka bootstrap, internal SCRAM | `kafka-lfg-kafka-bootstrap.glue.svc` | 9092 | Defined but not used by anything in this repo                                   |
| Schema Registry                 | `confluent-schema-registry.glue.svc` | 8081 | Plain HTTP inside the cluster; HTTPS only via Traefik                           |
| Keycloak                        | `keycloak.keycloak.svc`              | 8080 | Plain HTTP inside the cluster                                                   |

## Changing the domain

`global.projectDomain` is read by both `dev-glue` and `keycloak`. To use a different domain, override it on every
install or upgrade and update `/etc/hosts` to match:

```bash
helm upgrade --install -n glue glue charts/dev-glue \
  --set global.projectDomain=example.test --atomic
helm upgrade --install -n keycloak keycloak charts/keycloak \
  --set global.projectDomain=example.test --atomic
```

The broker certificate is reissued automatically because its SAN list is templated. Existing clients fail until you
regenerate `secrets/kafka/ca.crt` (the Strimzi cluster CA part stays the same, but the broker hostname changes) and
update your hosts file.
