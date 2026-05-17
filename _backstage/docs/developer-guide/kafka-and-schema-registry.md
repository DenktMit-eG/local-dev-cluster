# Kafka and Schema Registry

The cluster runs a single-broker Kafka 3.9.0 in KRaft mode and a Confluent Schema Registry 7.9.6. Both are created by
`charts/dev-glue`. Clients connect to Kafka over mTLS on `bootstrap.local.lgc:9094` and to the Schema Registry over
HTTPS on `sr.local.lgc`.

## Kafka client setup

After `./scripts/kind_setup.sh get-secrets` (or `make kind-create-local`), you have three files under
`secrets/kafka/`:

| File           | What it is                                                                                       |
|----------------|--------------------------------------------------------------------------------------------------|
| `user.p12`     | PKCS12 keystore containing the `kafka-super-user` mTLS identity issued by the Strimzi cluster CA |
| `userpass.txt` | Password for the keystore (single line, no trailing newline)                                     |
| `ca.crt`       | PEM bundle: mkcert root CA followed by the Strimzi cluster CA                                    |

The `kafka-super-user` is granted superuser privileges on the cluster (see `Kafka.spec.kafka.authorization.superUsers`),
which is convenient for development but does not represent a realistic production identity.

Connection settings for any Kafka client:

```properties
bootstrap.servers=bootstrap.local.lgc:9094
security.protocol=SSL
ssl.keystore.type=PKCS12
ssl.keystore.location=/path/to/secrets/kafka/user.p12
ssl.keystore.password=<content of userpass.txt>
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/secrets/kafka/ca.crt
```

For Spring Boot, the script also writes a ready-made `application.yaml` at the repository root.
See [Spring Boot Configuration](spring-boot-configuration.md).

For a one-off check from the host, the official Kafka tooling works:

```bash
kafka-topics.sh \
  --bootstrap-server bootstrap.local.lgc:9094 \
  --command-config kafka-client.properties \
  --list
```

…where `kafka-client.properties` contains the seven properties above.

## IntelliJ Big Data Tools

In the Kafka data source dialog, set the bootstrap server and switch the security tab to SSL:

```properties
security.protocol=SSL
bootstrap.servers=bootstrap.local.lgc:9094
ssl.keystore.type=PKCS12
ssl.keystore.location=/path/to/secrets/kafka/user.p12
ssl.keystore.password=<content of userpass.txt>
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/secrets/kafka/ca.crt
```

## Internal listeners

The `Kafka` resource exposes three listeners. Most of the time you only use the external one:

| Listener   | Port | Type       | Auth          | Used by                                      |
|------------|------|------------|---------------|----------------------------------------------|
| `plain`    | 9092 | internal   | SCRAM-SHA-512 | Available, not used by anything in the chart |
| `tls`      | 9093 | internal   | mTLS          | Schema Registry connects here                |
| `external` | 9094 | cluster-ip | mTLS          | Host clients via Traefik passthrough         |

If you deploy a service inside the cluster and want it to talk to Kafka, point it at the `tls` listener with
`bootstrap.servers=kafka-lfg-kafka-bootstrap.glue.svc:9093` and a `KafkaUser` identity, the same way Schema Registry
does. Going via the external listener from inside the cluster works but is wasteful.

## Schema Registry

The Schema Registry runs as a Deployment named `confluent-schema-registry` in the `glue` namespace. The image is the
standard Confluent Schema Registry (`confluentinc/cp-schema-registry:7.9.6`); it is provisioned indirectly through a
`StrimziSchemaRegistry` CR (apiGroup `roundtable.lsst.codes/v1beta1`), which the LSST Strimzi Registry Operator
reconciles into the Confluent deployment. The CR must carry a `strimzi.io/cluster: kafka-lfg` label so the operator
knows which Strimzi cluster to wire it to. The operator also handles wiring the registry's own `KafkaUser`
(`confluent-schema-registry`) and reading the keystore from the Strimzi-managed Secret.

It is reachable at:

```
https://sr.local.lgc
```

Schemas are persisted to the Kafka topic `registry-schemas` (one partition, compacted, single replica to match the
single-broker cluster). The topic is declared in `charts/dev-glue/templates/kafka/schema-topic.yaml`.

Quick sanity checks against the registry:

```bash
curl -s https://sr.local.lgc/subjects # list known subjects
curl -s https://sr.local.lgc/config # default compatibility level
curl -s https://sr.local.lgc/mode # READWRITE
```

A schema can be registered with the standard REST API. Spring Boot apps using `kafka-avro-serializer` only need
`schema.registry.url=https://sr.local.lgc` plus the same SSL trust store used for Kafka, since the registry presents a
cert from the same `default-cluster-issuer`.

## Useful kubectl commands

```bash
kubectl get kafka,kafkanodepool -n glue
kubectl get kafkauser,kafkatopic -n glue
kubectl get strimzischemaregistry -n glue
kubectl logs -n glue -l strimzi.io/cluster=kafka-lfg,strimzi.io/kind=Kafka
kubectl logs -n glue deploy/confluent-schema-registry
```

## Next

- [Spring Boot Configuration](spring-boot-configuration.md)
- [Network and TLS](../platform-overview/network-and-tls.md)
