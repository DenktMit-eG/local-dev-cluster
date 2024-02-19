# Module Foundation

This is the WiP Documentation for the foundation for module development.

## Prerequisites

1. Docker Installed https://www.docker.com/
2. Kind Installed https://kind.sigs.k8s.io/
3. Helm Installed https://helm.sh/docs/intro/install/
4. mkcert installed https://github.com/FiloSottile/mkcert?tab=readme-ov-file#installation

```mermaid
flowchart TD
    client --> controlPlane

    subgraph Computer
        subgraph docker
            subgraph kind
                controlPlane --> traefic
                traefic --> kafka
                traefic --> keycloak
            end
        end
    end
```


### Steps

Follow these steps to set up a local test environment

#### Create a local trusted root certificate authority

mkcert will create a rootCa that is trusted on your local maschine. Due to the installation of local kind cluster, a
secret containing the rootCa key is created so cert-manager will use it as a cluster issuer.

```shell
mkcert -install
```

#### Create Kind Cluster

```bash
kind create cluster --config=./kind/kind-cluster.yaml
```

After the installation is done, verify that correct context is used:

```shell
kubectl config current-context
```

It should print `kind-lgc`. If not see Set Context

### Prepare all needed helm charts

```shell
helm dep up charts/strimzi-kafka-operator
helm dep up charts/traefik 
helm dep up charts/cert-manager
```

### Installing the operators

```shell
export PROJECT_DOMAIN="local.lgc"
helm upgrade --install --create-namespace --namespace cert-manager cert-manager charts/cert-manager --atomic
helm upgrade --install --create-namespace --namespace traefik traefik charts/traefik --atomic
helm upgrade --install --create-namespace --namespace strimzi-kafka-operator strimzi-kafka-operator charts/strimzi-kafka-operator --atomic
kubectl create secret tls root-ca-secret \
  --cert="$(mkcert -CAROOT)/rootCA.pem" \
  --key="$(mkcert -CAROOT)/rootCA-key.pem" \
  --namespace=cert-manager
helm upgrade --install glue ./charts/dev-glue --atomic  --set "global.projectDomain=${PROJECT_DOMAIN}"
helm upgrade --install --create-namespace --atomic  --namespace keycloak keycloak ./charts/keycloak  --set "global.projectDomain=${PROJECT_DOMAIN}"
```

### get kafka secret

```shell
kubectl get secrets kafka-super-user -o jsonpath='{.data.user\.password}' | base64 -d > userpass.txt
cat "$(mkcert -CAROOT)/rootCA.pem"  > ca.crt
kubectl get secrets kafka-super-user -o jsonpath='{.data.ca\.crt}' | base64 -d >> ca.crt
kubectl get secrets kafka-super-user -o jsonpath='{.data.user\.p12}' | base64 -d > user.p12 
```

### Kafka Settings for Big Datatools in Intellij

Please replace the `[PATH_TO_CERT]` and `[content of userpass.txt]` with the config below

```properties
security.protocol=SSL
bootstrap.servers=bootstrap.local.lgc:9094
ssl.keystore.type=PKCS12
ssl.keystore.location=[PATH_TO_CERT]/user.p12
ssl.keystore.password=[content of userpass.txt]
ssl.truststore.type=PEM
ssl.truststore.location=[PATH_TO_CERT]/ca.crt
```

### Accessing your Ingresses

To access your ingresses you should add them to your /etc/hosts

```bash
127.0.0.1       keycloak.local.lgc
127.0.0.1       bootstrap.local.lgc
```

### Set Context (also happens after cluster creation)

```bash
kind export kubeconfig --name lgc
```

#### Clean up

```bash
kind delete cluster --name lgc
```

## Keycloak Sandbox realm

keycloak is running in dev mode

### Users

* admin:admin
* reader:reader
* writer:writer

### Groups:

* admins
* readers
* writers

### Roles:

* admin-action
* reader-action
* writer-action

### Public client sandbox-ui

Usage within

```typescript
import {AuthProviderProps} from "react-oidc-context";

const oidcConfig: AuthProviderProps = {
    authority: "https://keycloak.local.lgc/realms/sandbox",
    client_id: "sandbox-ui",
    redirect_uri: document.baseURI,
};
```
