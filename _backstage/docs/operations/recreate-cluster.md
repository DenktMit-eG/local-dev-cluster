# Recreate Cluster

The cluster is meant to be disposable. When something is wrong and the cause is not obvious, recreating is usually
faster than debugging.

## With Make

```bash
make kind-recreate-local
```

The target deletes the `lgc` cluster and runs the create flow from `scripts/kind_setup.sh`. After it finishes, the
`secrets/kafka/` files and `application.yaml` reflect the new credentials.

## By hand

```bash
./scripts/kind_setup.sh delete-cluster
./scripts/kind_setup.sh create-cluster
./scripts/kind_setup.sh get-secrets
```

The two-step form is useful if you want to inspect the cluster between recreate and credential extraction, for example
to wait on a specific pod yourself.

## What disappears

| Artifact                                            | Survives recreate?                                                                                    |
|-----------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| Kafka topics, messages                              | No. The kind nodes are deleted, which removes the Docker volumes backing the Kafka broker PVCs        |
| Schema Registry subjects                            | No. The data lives in the `registry-schemas` topic                                                    |
| Keycloak realm changes made through the UI          | No. The realm is re-imported from the JSON on every pod start                                         |
| `secrets/kafka/` and `application.yaml` on the host | Yes, but they no longer match the new cluster. Rerun `get-secrets`                                    |
| `/etc/hosts` entries                                | Yes                                                                                                   |
| mkcert root CA                                      | Yes; only `mkcert -uninstall` removes it                                                              |

## What you do not need to recreate

The mkcert root CA stays installed across cluster recreates. The setup script reads it from `$(mkcert -CAROOT)` again
and recreates `root-ca-secret` automatically.

## After the recreate

```bash
kubectl get pods -A
kubectl get certificate -A
kubectl get kafka,kafkanodepool -n glue
```

Kafka takes the longest to become ready. When
`kubectl get kafka -n glue -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'` returns `True`, the
Schema Registry and any client can connect.

## When recreate is not enough

If the recreate itself fails (the script reports a Helm timeout or `helm dep up` cannot pull the upstream charts),
see [Troubleshooting](troubleshooting.md). A failed recreate usually leaves a partial cluster behind that should be
deleted before retrying.

## Next

- [Retrieve Secrets](retrieve-secrets.md)
- [Troubleshooting](troubleshooting.md)
