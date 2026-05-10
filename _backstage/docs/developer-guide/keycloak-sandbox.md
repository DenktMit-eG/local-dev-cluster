# Keycloak Sandbox

Keycloak runs from `charts/keycloak` in development mode (`start-dev --import-realm`). The `sandbox` realm is imported
from `charts/keycloak/files/realm-sandbox.json` on every pod start, so any change made through the admin UI is lost on
restart. To persist a change, edit the JSON and roll the pod.

## Endpoints

| Endpoint        | URL                                                                          |
|-----------------|------------------------------------------------------------------------------|
| Account console | `https://keycloak.local.lgc/realms/sandbox/account`                          |
| Admin console   | `https://keycloak.local.lgc` (login as `admin` / `admin`)                    |
| OIDC discovery  | `https://keycloak.local.lgc/realms/sandbox/.well-known/openid-configuration` |

The realm `sslRequired` is set to `external`, which means HTTPS is required from anything other than localhost. Traefik
already terminates HTTPS for `keycloak.local.lgc`, so this is the normal case.

## Users

| Username | Password | Groups    |
|----------|----------|-----------|
| `admin`  | `admin`  | `admins`  |
| `reader` | `reader` | `readers` |
| `writer` | `writer` | `writers` |

These passwords are imported from the realm JSON in plaintext and are intentionally trivial. Do not reuse them anywhere
outside this local cluster.

## Groups and realm roles

Groups carry realm roles, which is what your application receives in the `groups` claim if you map them.

| Group     | Realm roles                                                            |
|-----------|------------------------------------------------------------------------|
| `admins`  | `admin-action`, `write-action`, `read-action`, `default-roles-sandbox` |
| `writers` | `write-action`, `read-action`                                          |
| `readers` | `read-action`                                                          |

The custom realm roles are `read-action`, `write-action`, and `admin-action`. The repository README mentions
`reader-action` / `writer-action`; the realm JSON is the authoritative source and uses the names listed above.

## sandbox-ui client

`sandbox-ui` is the public OIDC client meant for browser-based applications. It is configured for the standard
authorization-code flow with PKCE.

| Property             | Value                                                    |
|----------------------|----------------------------------------------------------|
| Client ID            | `sandbox-ui`                                             |
| Public client        | yes                                                      |
| Standard flow        | enabled                                                  |
| Direct access grants | enabled                                                  |
| Redirect URIs        | `*`                                                      |
| Web origins          | `*`                                                      |
| Default scopes       | `web-origins`, `acr`, `profile`, `roles`, `email`        |
| Optional scopes      | `address`, `phone`, `offline_access`, `microprofile-jwt` |

The wildcard redirect URI is fine for local development and unsafe anywhere else. If you copy this realm into another
environment, replace `*` with the specific redirect URIs of your apps.

### Use from a React app

```typescript
import { AuthProviderProps } from "react-oidc-context";

const oidcConfig: AuthProviderProps = {
  authority: "https://keycloak.local.lgc/realms/sandbox",
  client_id: "sandbox-ui",
  redirect_uri: document.baseURI,
};
```

### Use from a Spring Boot resource server

A typical `application.yaml` snippet:

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://keycloak.local.lgc/realms/sandbox
```

The JVM has to trust the mkcert root, otherwise the JWT issuer URI lookup fails with a TLS error. Either run
`mkcert -install` (which adds the root to most JDK trust stores via PKCS12 files) or import the root explicitly.

## Token lifespans

Defaults from the realm JSON:

| Setting               | Value     |
|-----------------------|-----------|
| Access token lifespan | 300 s     |
| SSO idle timeout      | 1800 s    |
| SSO max lifespan      | 36000 s   |
| Offline session max   | 5184000 s |

Short access token lifespans force more refresh-token traffic during development and surface refresh issues quickly.

## Other clients in the realm

The realm also contains the standard Keycloak system clients (`account`, `account-console`, `admin-cli`, `broker`,
`realm-management`, `security-admin-console`). They exist for Keycloak itself; do not reuse them for your applications.

## Next

- [Spring Boot Configuration](spring-boot-configuration.md)
- [Accessing Services](../getting-started/accessing-services.md)
