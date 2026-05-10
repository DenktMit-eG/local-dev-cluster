# Accessing Services

Every service is reached through Traefik on a hostname under `local.lgc`. Browser-facing services use HTTPS with
mkcert-issued certificates. Kafka uses mTLS on port 9094 with TLS passthrough.

## Hosts file

Add these to `/etc/hosts` (or the Windows equivalent):

```
127.0.0.1   keycloak.local.lgc
127.0.0.1   sr.local.lgc
127.0.0.1   bootstrap.local.lgc
127.0.0.1   b0.local.lgc
```

`bootstrap.local.lgc` is the Kafka bootstrap address. `b0.local.lgc` is broker 0; the broker advertises this hostname
during the metadata exchange, so it must resolve from the client machine. Adding more brokers means adding more
`bN.local.lgc` entries and updating the Traefik routes; see [Architecture](../platform-overview/architecture.md).

## Browser endpoints

| Service                   | URL                          | Credentials          |
|---------------------------|------------------------------|----------------------|
| Keycloak admin console    | `https://keycloak.local.lgc` | `admin` / `admin`    |
| Confluent Schema Registry | `https://sr.local.lgc`       | none (HTTP API only) |

If the browser shows a certificate warning, the mkcert root CA is not in your trust store. Run `mkcert -install` and
reload the page; the existing leaf certificates remain valid because they are signed by the same root.

## Kafka endpoint

```
bootstrap.local.lgc:9094
```

The connection is mTLS. Clients authenticate with the `kafka-super-user` PKCS12 keystore at `secrets/kafka/user.p12` and
trust the chain in `secrets/kafka/ca.crt`.
See [Kafka and Schema Registry](../developer-guide/kafka-and-schema-registry.md) for the client configuration.

## Quick check

The two commands below confirm Traefik is fronting the right services:

```bash
curl -sI https://keycloak.local.lgc | head -1            # HTTP/2 200 (after Keycloak finishes starting)
curl -sI https://sr.local.lgc/subjects | head -1         # HTTP/2 200
```

For Kafka, an `openssl s_client` probe to `bootstrap.local.lgc:9094` should show a certificate signed by the mkcert
root.

## Next

- [Kafka and Schema Registry](../developer-guide/kafka-and-schema-registry.md)
- [Keycloak Sandbox](../developer-guide/keycloak-sandbox.md)
