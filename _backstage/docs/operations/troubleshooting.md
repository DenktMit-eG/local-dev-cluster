# Troubleshooting

This page covers failure modes that come up while bringing the cluster up or while connecting to it. For each, the
diagnostic comes first and the fix follows.

## Wrong kube context

```bash
kubectl config current-context
```

Expected: `kind-lgc`. If you see a different context, point kubectl back at the kind cluster:

```bash
kind export kubeconfig --name lgc
```

If `kind get clusters` does not list `lgc` at all, the cluster was deleted or never created. Run
`earthly +kind-create-local`.

## Certificate not trusted in the browser

The mkcert root is missing from your trust store, or the cluster issued certificates against a different root.

```bash
mkcert -install
kubectl get secret root-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -fingerprint
mkcert -CAROOT
openssl x509 -in "$(mkcert -CAROOT)/rootCA.pem" -noout -fingerprint
```

The two fingerprints must match. If they do not, recreate the `root-ca-secret`:

```bash
kubectl delete secret root-ca-secret -n cert-manager
kubectl create secret tls root-ca-secret \
  --cert="$(mkcert -CAROOT)/rootCA.pem" \
  --key="$(mkcert -CAROOT)/rootCA-key.pem" \
  --namespace=cert-manager
```

cert-manager re-issues the leaf certificates within a few seconds.

## `helm dep up` fails

The wrapper charts pull their upstream chart archives over HTTP. A failure usually means a transient network problem or
that the chart repository moved.

```bash
helm dep up charts/cert-manager
helm dep up charts/traefik
helm dep up charts/strimzi-kafka-operator
helm dep up charts/strimzi-registry-operator
```

If a single chart fails repeatedly, check `Chart.yaml` for the repository URL; the script does not run `helm repo add`
for you.

## Hostnames do not resolve

Kafka clients fail with `UnknownHostException`, browsers cannot reach `keycloak.local.lgc`. Verify `/etc/hosts`:

```bash
grep local.lgc /etc/hosts
```

Expected:

```
127.0.0.1   keycloak.local.lgc
127.0.0.1   sr.local.lgc
127.0.0.1   bootstrap.local.lgc
127.0.0.1   b0.local.lgc
```

If only `bootstrap.local.lgc` is present, Kafka connects but fails on the first metadata response when the broker
advertises `b0.local.lgc`. Both entries are required.

## Kafka client cannot connect

Check, in order:

1. Traefik pods running: `kubectl get pods -n traefik`
2. Kafka cluster ready: `kubectl get kafka -n glue`
3. The `IngressRouteTCP` exists: `kubectl get ingressroutetcp -n glue`
4. The keystore is non-empty: `test -s secrets/kafka/user.p12 && echo ok`
5. The trust bundle has two certificates: `awk '/BEGIN CERT/{c++} END{print c}' secrets/kafka/ca.crt` should print `2`

If only the trust bundle is wrong, regenerate with `./scripts/kind_setup.sh get-secrets`.

A quick TCP probe to the bootstrap endpoint:

```bash
openssl s_client -connect bootstrap.local.lgc:9094 -servername bootstrap.local.lgc \
  -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
```

You should see the broker subject and the Strimzi cluster CA as the issuer.

## `kubectl get certificate -A` shows `Ready=False`

cert-manager could not issue a certificate. Two common causes:

1. `root-ca-secret` is missing in the `cert-manager` namespace. Recreate it as shown in the certificate-not-trusted
   section above.
2. `default-cluster-issuer` is not yet reconciled. `kubectl describe clusterissuer default-cluster-issuer` shows the
   reason.

The issuer is created by `dev-glue`, so a missing `default-cluster-issuer` usually means the `dev-glue` install failed;
check `helm list -n glue` and the `kubectl describe` of the failing resource.

## Schema topic shows `replicas: 3` warnings

The `registry-schemas` topic is declared with `replicas: 3` but the cluster has one broker. Strimzi creates the topic
anyway; the warning is benign for development. To make the warning go away, either lower the topic replication factor in
`charts/dev-glue/templates/kafka/schema-topic.yaml` or scale the `KafkaNodePool` to three replicas.

## `kafka-super-user` Secret is empty

The setup script protects against this with a 15-second sleep, but if you extracted the secret manually right after pod
start, you may have caught the operator mid-write:

```bash
kubectl get secret -n glue kafka-super-user -o jsonpath='{.data}' | wc -c
```

A value below ~3000 bytes means the secret has not been populated. Wait, then re-run
`./scripts/kind_setup.sh get-secrets`.

## Reset everything

When the failure mode is unclear, recreate:

```bash
earthly +kind-recreate-local
```

See [Recreate Cluster](recreate-cluster.md) for what survives a recreate and what does not.
