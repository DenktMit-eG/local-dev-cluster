# Retrieve Secrets

The Kafka client material lives in a Strimzi-managed Secret called `kafka-super-user` in the `glue` namespace. The setup
script exports the parts you need to disk and combines them with the local mkcert root.

## Run the script

```bash
./scripts/kind_setup.sh get-secrets
```

It writes four files:

| Path                         | Source                                                         | Used for                                                       |
|------------------------------|----------------------------------------------------------------|----------------------------------------------------------------|
| `secrets/kafka/userpass.txt` | `kafka-super-user.data."user.password"`                        | PKCS12 keystore password                                       |
| `secrets/kafka/user.p12`     | `kafka-super-user.data."user.p12"`                             | Client keystore (mTLS identity)                                |
| `secrets/kafka/ca.crt`       | `mkcert -CAROOT/rootCA.pem` + `kafka-super-user.data."ca.crt"` | Trust bundle: mkcert root and Strimzi cluster CA, concatenated |
| `application.yaml`           | Heredoc in the script                                          | Spring Boot configuration that points at the three files above |

The `ca.crt` bundle is the concatenation in that order on purpose. The mkcert root is needed for HTTPS to
`sr.local.lgc` (issued by `default-cluster-issuer` against the mkcert root); the Strimzi cluster CA is needed for the
Kafka mTLS handshake (issued by Strimzi's internal CA, which mkcert does not sign).

## The 15-second sleep

Near the top of `KIND_GET_SECRETS`, the script sleeps for 15 seconds before reading the secret. That is a workaround
for [kubernetes/kubernetes#122994](https://github.com/kubernetes/kubernetes/pull/122994): under some conditions, the
operator-created Secret reports an empty `data` map for a brief window even though `kubectl get` shows it as Present.
The sleep is enough to clear that window. Do not remove it; the failure mode is silent and writes a zero-byte
`user.p12`.

## Verify the files

```bash
test -s secrets/kafka/user.p12 || echo "empty keystore"
test -s secrets/kafka/userpass.txt || echo "empty password"
openssl pkcs12 -in secrets/kafka/user.p12 \
  -passin "file:secrets/kafka/userpass.txt" -info -nokeys | head
```

The keystore should contain a single key entry with the friendly name `kafka-super-user`. The bundle should list two
certificates:

```bash
awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c++} END{print c " certs in ca.crt"}' \
  secrets/kafka/ca.crt
```

Expected output: `2 certs in ca.crt`.

## After a recreate

`make kind-recreate-local` reissues the `kafka-super-user` Secret with new contents and a new
password. Anything still using the old `secrets/kafka/` files will fail the TLS handshake. Rerun the script:

```bash
./scripts/kind_setup.sh get-secrets
```

## Manual extraction

If the script is unavailable or you only need one piece, the equivalent commands are:

```bash
kubectl get secret -n glue kafka-super-user \
  -o jsonpath='{.data.user\.password}' | base64 -d > secrets/kafka/userpass.txt

kubectl get secret -n glue kafka-super-user \
  -o jsonpath='{.data.user\.p12}' | base64 -d > secrets/kafka/user.p12

cat "$(mkcert -CAROOT)/rootCA.pem" > secrets/kafka/ca.crt
kubectl get secret -n glue kafka-super-user \
  -o jsonpath='{.data.ca\.crt}' | base64 -d >> secrets/kafka/ca.crt
```

## Next

- [Spring Boot Configuration](../developer-guide/spring-boot-configuration.md)
- [Troubleshooting](troubleshooting.md)
