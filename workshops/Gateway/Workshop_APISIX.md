# Workshop APISIX - Grafana Access via Gateway API

## Introduction

APISIX is a cloud-native API gateway that uses the Kubernetes **Gateway API** standard for routing.

### Simplified Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │      KUBERNETES (Gateway API)                │
                    │                                              │
   [Browser] ──▶    │  ┌─────── Gateway ───────┐                   │
   or curl          │  │  (entry point)        │                   │
                    │  │       │               │                   │
                    │  │  HTTPRoute ────► Service                  │
                    │  │  TLS refs ───────► Secret TLS             │
                    │  │       │                                   │
                    │  │  Certificate ──► Secret TLS ◀── cert-     │
                    │  │                     manager               │
                    │  └──────────────────────┘                    │
                    └──────────────────────────────────────────────┘
                              │
                              │ APISIX Ingress Controller
                              ▼
                    ┌──────────────────────────────────────────────┐
                    │         APISIX (Implementation)              │
                    │                                              │
                    │  GatewayProxy → Routes / SSL / Upstreams     │
                    │                           ◀──► etcd          │
                    └──────────────────────────────────────────────┘
```

### Definitions

| Zone | Description |
|------|-------------|
| **Top: Kubernetes** | Standardized Gateway API resources (Gateway, HTTPRoute, Certificate) |
| **Bottom: APISIX** | Internal implementation (GatewayProxy, APISIX routes, SSL) |

### Components

| Resource | Type | Role |
|----------|------|------|
| GatewayClass | K8s Standard | Defines the APISIX controller |
| Gateway | K8s Standard | Entry point (http/https) |
| HTTPRoute | K8s Standard | Routing rules |
| Certificate | cert-manager | TLS certificate request |
| GatewayProxy | APISIX | Admin API configuration |
| APISIX Routes | Internal | Routes in APISIX |

---

## Objective

Deploy APISIX as an Ingress/Gateway controller and expose Grafana via an HTTPRoute.

## Prerequisites

- Working Kubernetes cluster
- Helm installed
- `kubectl` configured
- kube-prometheus-stack installed and working (namespace kube-monitoring)

## Configuration Files

| File | Role |
|---------|------|
| `helm/apisix/gateway-apisix.yml` | APISIX proxy configuration |
| `helm/apisix/ingress-controller-apisix.yml` | Ingress Controller configuration |

## Target Architecture

```
Client → APISIX Gateway → HTTPRoute → prometheus-grafana:80
                                (kube-monitoring)
```

## Steps

### 1. Add APISIX Repository

```bash
helm repo add apisix https://charts.apiseven.com
helm repo update
```

### 2. Install APISIX

**Prerequisites**: Modify credentials in values files before installation:
- `scripts/helm/apisix/gateway-apisix.yml`: replace `<CREDENTIAL_ADMIN>` and `<CREDENTIAL_VIEWER>`
- `scripts/helm/apisix/ingress-controller-apisix.yml`: replace `<CREDENTIAL_ADMIN>` (must be identical to gateway-apisix.yml)

> **Important**: All occurrences of `<CREDENTIAL_ADMIN>` (in `gateway-apisix.yml`, `ingress-controller-apisix.yml`, and the GatewayProxy below) must use the **same value**.

> **Network note**: The Kubernetes pods CIDR must be added to `allow` so the Ingress Controller can communicate with APISIX admin API.
> To find the CIDR: `kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'`

**Important**: Do not commit real credentials to git.

```bash
helm -n kube-gateway upgrade --install apisix apisix/apisix --version 2.13.0 -f helm/apisix/gateway-apisix.yml
```

### 3. Verify Installation

```bash
kubectl -n kube-gateway get pods
kubectl -n kube-gateway get svc
```

### 4. Create GatewayProxy

The GatewayProxy defines the connection configuration between the Ingress Controller and APISIX. It must be created **after** APISIX and **before** the Ingress Controller.

**Documentation:** [Gateway API Concepts](https://apisix.apache.org/docs/ingress-controller/concepts/gateway-api-apisix/)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apisix.apache.org/v1alpha1
kind: GatewayProxy
metadata:
  name: apisix-ingress-controller-config
  namespace: kube-gateway
spec:
  provider:
    type: ControlPlane
    controlPlane:
      service:
        name: apisix-admin
        port: 9180
      auth:
        type: AdminKey
        adminKey:
          value: <CREDENTIAL_ADMIN>
EOF
```

### 5. Install APISIX Ingress Controller

The Ingress Controller manages Gateway API resources (HTTPRoute, etc.) and automatically creates Gateway API CRDs.

```bash
helm -n kube-gateway upgrade --install apisix-ingress-controller apisix/apisix-ingress-controller --version 1.1.2 -f helm/apisix/ingress-controller-apisix.yml
```

### 6. Create GatewayClass

The GatewayClass must be created manually. It tells APISIX to handle this class.

**Documentation:** [APISIX Gateway API Examples](https://apisix.apache.org/docs/ingress-controller/reference/apisix-ingress-controller/examples/)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: apisix
spec:
  controllerName: apisix.apache.org/apisix-ingress-controller
EOF
```

### 7. Create Gateway (gw-http)

Represents the traffic entry point.

**Prerequisites:** Add the `gateway=enabled` label to namespaces containing HTTPRoutes:
```bash
kubectl label namespace <NAMESPACE> gateway=enabled
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-http
  namespace: kube-gateway
spec:
  gatewayClassName: apisix
  infrastructure:
    parametersRef:
      group: apisix.apache.org
      kind: GatewayProxy
      name: apisix-ingress-controller-config
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway: "enabled"
EOF
```

### 8. Verify Gateway

```bash
kubectl get gateway -n kube-gateway
```

### 9. Identify APISIX Gateway Service

```bash
kubectl -n kube-gateway get svc
```

**Expected services:**
- `apisix-gateway`: Traffic entry point (NodePort or LoadBalancer)
- `apisix-admin`: APISIX administration API (ClusterIP)

**Access URL:** `http://<NODE_IP>:<NODE_PORT>/`

### 10. Create HTTPRoute (hr-grafana)

The HTTPRoute is created in the application namespace (kube-monitoring) and references the Gateway (kube-gateway).

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-http
      namespace: kube-gateway
  hostnames:
    - "grafana.local"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: prometheus-grafana
          port: 80
EOF
```

**Notes:**
- `hostnames` must match a DNS entry or be added in `/etc/hosts`
- For a path-based route without hostname, remove the `hostnames` section

### 11. Install cert-manager and Create ClusterIssuer

cert-manager manages TLS certificates via Let's Encrypt.

**Prerequisites:** Modify `<EMAIL>` with a valid email for Let's Encrypt.

**Note:** SSL is disabled by default in the APISIX chart. See [APISIX values.yaml](https://github.com/apache/apisix-helm-chart/blob/master/charts/apisix/values.yaml#L229) (`apisix.ssl.enabled`).

**2-step installation** (CRDs then Helm):

```bash
# Step 1: Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml

# Step 2: Install cert-manager WITHOUT CRDs
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace kube-gateway \
  --version v1.13.1 \
  --set crds.enabled=false \
  --set "extraArgs={--feature-gates=ExperimentalGatewayAPISupport=true}"
```

> **Note**: This 2-step installation is necessary to avoid timeouts. CRDs are large and installation can fail if you try to install them at the same time as cert-manager.

#### ClusterIssuer with gatewayHTTPRoute

For HTTP-01 challenge with Gateway API, use `gatewayHTTPRoute` instead of `ingress`.

**Documentation:** [cert-manager Gateway API](https://cert-manager.io/docs/usage/gateway/)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: gw-monitoring-https
                namespace: kube-gateway
EOF
```
> **Note**: The HTTP-01 challenge requires port 80 to be publicly accessible for certificate validation.

> **Important**: cert-manager requires the feature gate `ExperimentalGatewayAPISupport=true` to support Gateway API.
> See [cert-manager Gateway API documentation](https://cert-manager.io/docs/usage/gateway/)

> **Architecture note**: For a clean architecture with minimal resources in the application namespace (`kube-monitoring`), the Gateway is created in `kube-gateway` with `allowedRoutes.namespaces.from: All` to allow HTTPRoutes from all namespaces. See the [Recommended Architecture](#recommended-architecture) section for more details.


#### Gateway gw-https avec listener HTTPS

**Documentation** : [Gateway API - allowedRoutes](https://gateway-api.sigs.k8s.io/api-types/gateway/), [APISIX Issue #2727](https://github.com/apache/apisix-ingress-controller/issues/2727)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-monitoring-https
  namespace: kube-gateway
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  gatewayClassName: apisix
  infrastructure:
    parametersRef:
      group: apisix.apache.org
      kind: GatewayProxy
      name: apisix-ingress-controller-config
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "grafana.famille-paquin.fr"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: grafana-monitoring-tls
            kind: Secret
            group: ""
EOF
```

#### HTTPRoute redirect HTTP → HTTPS

**Documentation** : [Gateway API - HTTP to HTTPS redirect](https://gateway-api.sigs.k8s.io/guides/http-redirect-rewrite/#http-to-https-redirects)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-redirect
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-monitoring-https
      namespace: kube-gateway
      sectionName: http
  hostnames:
    - "grafana.famille-paquin.fr"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            hostname: "grafana.famille-paquin.fr"
            statusCode: 301
EOF
```

#### HTTPRoute traffic HTTPS vers Grafana

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-https
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-monitoring-https
      namespace: kube-gateway
      sectionName: https
  hostnames:
    - "grafana.famille-paquin.fr"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: prometheus-grafana
          port: 80
EOF
```

---

## Chapter 12: Rate Limiting with APISIX

### 12.1 Introduction

Rate limiting allows controlling the number of requests allowed to a service. This is useful for:
- Protecting against abuse and DDoS attacks
- Implementing API monetization (per-request quotas)
- Ensuring quality of service (QoS)

### 12.2 Available Plugins

APISIX offers two plugins for rate limiting:

| Plugin | Type | Granularité |
|--------|------|-------------|
| `limit-req` | Leaky bucket | Requêtes par seconde (QPS) |
| `limit-count` | Fixed window | Requêtes dans un temps configurable |

---

### 12.3 Plugin limit-req

#### Fonctionnement

The `limit-req` plugin uses the **leaky bucket** algorithm. It limits the number of requests per second and can delay excess requests.

#### Main Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `rate` | integer | ✅ | - | Number of requests allowed per second |
| `burst` | integer | ✅ | - | Number of additional requests allowed (delay) |
| `key` | string | ❌ | `remote_addr` | Limitation key (`remote_addr`, `consumer_name`, etc.) |
| `key_type` | string | ❌ | `var` | Type of key (`var`, `var_combination`) |
| `rejected_code` | integer | ❌ | 503 | HTTP code returned on rejection |
| `nodelay` | boolean | ❌ | false | If true, do not delay requests |
| `policy` | string | ❌ | `local` | Storage (`local`, `redis`, `redis-cluster`) |

#### Configuration Example

```json
{
  "plugins": {
    "limit-req": {
      "rate": 10,
      "burst": 5,
      "key": "remote_addr",
      "rejected_code": 429,
      "nodelay": true
    }
  }
}
```

- 10 requests per second allowed
- 5 additional requests can be delayed
- Returns 429 (Too Many Requests) if exceeded

---

### 12.4 Plugin limit-count

#### Operation

The `limit-count` plugin uses a **fixed window** algorithm. It limits the number of requests in a given time interval.

#### Main Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `count` | integer | ✅ | - | Number of requests allowed |
| `time_window` | integer | ✅ | - | Interval in **seconds** |
| `key` | string | ❌ | `remote_addr` | Limitation key |
| `key_type` | string | ❌ | `var` | Type of key (`var`, `var_combination`, `constant`) |
| `rejected_code` | integer | ❌ | 503 | HTTP code returned on rejection |
| `policy` | string | ❌ | `local` | Storage (`local`, `redis`, `redis-cluster`) |
| `show_limit_quota_header` | boolean | ❌ | true | Add X-RateLimit-* headers |

#### Examples for different time periods

| Time Period | time_window | Configuration |
|-------------|------------|----------------|
| 1 second | 1 | `count: 100, time_window: 1` |
| 1 minute | 60 | `count: 1000, time_window: 60` |
| 1 hour | 3600 | `count: 10000, time_window: 3600` |
| 1 day | 86400 | `count: 50000, time_window: 86400` |

#### Example for 100 requests/day

```json
{
  "plugins": {
    "limit-count": {
      "count": 100,
      "time_window": 86400,
      "key": "remote_addr",
      "rejected_code": 429,
      "show_limit_quota_header": true
    }
  }
}
```

#### Response Headers

When a request exceeds the quota, APISIX returns informative headers:
- `X-RateLimit-Limit`: Total quota
- `X-RateLimit-Remaining`: Remaining quota
- `X-RateLimit-Reset`: Seconds until reset

#### Key Options

The `key` attribute allows limiting requests by different identifiers:

| Key | Description | Use Case |
|-----|-------------|----------|
| `remote_addr` | Client IP address | Default, IP-based limiting |
| `server_addr` | Server IP address | Service-level limiting |
| `http_x_real_ip` | X-Real-IP header | Behind proxy |
| `http_x_forwarded_for` | X-Forwarded-For header | CDN/proxy chains |
| `consumer_name` | Authenticated consumer | Per-user limiting |
| `service_id` | Service ID | Per-service limiting |

##### key_type Options

| key_type | Description | Example |
|----------|-------------|---------|
| `var` | Single variable (default) | `key: consumer_name` |
| `var_combination` | Multiple variables | `key: "$remote_addr $consumer_name"` |
| `constant` | Fixed value | `key: "api-tier-free"` |

##### Usage Examples

**Per IP (default):**
```yaml
key: remote_addr
key_type: var
```

**Per authenticated user (requires auth):**
```yaml
key: consumer_name
key_type: var
```

**IP + User combined:**
```yaml
key: "$remote_addr $consumer_name"
key_type: var_combination
```

**By custom header:**
```yaml
key: http_x_api_key
key_type: var
```

---

### 12.5 Implementation with Gateway API

To apply rate limiting plugins with Gateway API, use the `PluginConfig` CRD.

#### PluginConfig Installation

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  name: limit-req-plugin
  namespace: kube-gateway
spec:
  plugins:
    - name: limit-req
      config:
        rate: 10
        burst: 5
        key: remote_addr
        rejected_code: 429
        nodelay: true
EOF
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  name: limit-count-plugin
  namespace: kube-gateway
spec:
  plugins:
    - name: limit-count
      config:
        count: 100
        time_window: 86400
        key: remote_addr
        rejected_code: 429
        show_limit_quota_header: true
EOF
```

> **Important**: The PluginConfig must be in the **same namespace** as the HTTPRoute, OR a ReferenceGrant must authorize cross-namespace access. Without proper authorization, the plugin will silently not be applied.

#### HTTPRoute Association

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-rate-limited
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-monitoring-https
      namespace: kube-gateway
      sectionName: https
  hostnames:
    - "grafana.famille-paquin.fr"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/
      backendRefs:
        - name: prometheus-grafana
          port: 80
      filters:
        - type: ExtensionRef
          extensionRef:
            group: apisix.apache.org
            kind: PluginConfig
            name: limit-count-plugin
EOF
```

> **Note**: For production, ensure PluginConfig is in the same namespace as HTTPRoute, or use ReferenceGrant for cross-namespace access.

#### Cross-Namespace Reference with ReferenceGrant

If the PluginConfig is in a different namespace than the HTTPRoute, use a ReferenceGrant to authorize the access.

**Example:**
- PluginConfig: `kube-gateway` namespace
- HTTPRoute: `kube-monitoring` namespace

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-httproute-to-plugins
  namespace: kube-gateway
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: kube-monitoring
  to:
    - group: apisix.apache.org
      kind: PluginConfig
      name: limit-count-plugin
EOF
```

> **Note**: The ReferenceGrant must be in the **target** namespace (where the PluginConfig is).

---

### 12.6 Comparison and Use Cases

| Aspect | limit-req | limit-count |
|--------|----------|------------|
| **Algorithm** | Leaky bucket | Fixed window |
| **Burst** | ✅ Yes | ❌ No |
| **Minimum time** | 1 second | 1 second |
| **Maximum time** | - | Infinite |
| **Performance** | Very high | High |
| **Main usage** | QPS protection | Time quotas |

#### Comparison Table

| Use Case | Recommended Plugin |
|-------------|----------------|
| DDoS / abuse protection | `limit-req` |
| 100 requests/second | `limit-req` |
| 1000 requests/day | `limit-count` |
| Paid API (X req/month) | `limit-count` |
| Per-user rate limiting | `limit-req` or `limit-count` with `key: consumer_name` |

---

### 12.7 Plugin Combination

Both plugins **can be combined** on the same route. They execute in priority order:

1. `limit-req` (priority 1001) - controls QPS
2. `limit-count` (priority 1002) - controls time quota

#### Combined Configuration Example

```json
{
  "plugins": {
    "limit-req": {
      "rate": 10,
      "burst": 5,
      "key": "remote_addr",
      "rejected_code": 429
    },
    "limit-count": {
      "count": 1000,
      "time_window": 3600,
      "key": "remote_addr",
      "rejected_code": 429
    }
  }
}
```

This allows:
- Maximum 10 requests/second
- Maximum 1000 requests/hour

#### Combined PluginConfig

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apisix.apache.org/v1alpha1
kind: PluginConfig
metadata:
  name: rate-limit-combined
  namespace: kube-gateway
spec:
  plugins:
    - name: limit-req
      config:
        rate: 10
        burst: 5
        key: remote_addr
        rejected_code: 429
    - name: limit-count
      config:
        count: 1000
        time_window: 3600
        key: remote_addr
        rejected_code: 429
        show_limit_quota_header: true
EOF
```

---

### 12.8 Storage Policy

The `policy` parameter defines where the counter is stored:

| Policy | Description | Recommended Usage |
|--------|-------------|--------------|
| `local` | In-memory counter on each node | Single node, low latency |
| `redis` | Shared counter via Redis | Multi-node cluster, shared quota |
| `redis-cluster` | Counter via Redis Cluster | High availability |

#### Example with Redis

```json
{
  "plugins": {
    "limit-count": {
      "count": 100,
      "time_window": 3600,
      "policy": "redis",
      "redis_host": "redis-service",
      "redis_port": 6379,
      "key": "remote_addr"
    }
  }
}
```

---

### 12.9 Recommendations

#### Choosing the Right Plugin

| Need | Solution |
|--------|----------|
| Basic protection (QPS) | `limit-req` with `rate: 10-100` |
| Daily quotas | `limit-count` with `time_window: 86400` |
| Multi-nodes | Use `policy: redis` |
| Combination | Both plugins combined |

#### Best Practices

- **Start conservative**: Begin with low limits and adjust
- **Use Redis in production**: For multi-node consistency
- **Configure rejected_code**: Return 429 (Too Many Requests) for better client integration
- **Add headers**: `show_limit_quota_header: true` to inform clients

---

## Notes

### Admin API APISIX

The Admin API allows managing APISIX from the command line. It is the backend equivalent of the Dashboard (which is **deprecated**).

**Port-forward to the Admin API:**
```bash
kubectl -n kube-gateway port-forward svc/apisix-admin 9180:9180 &
```

> **Note**: To access from outside the cluster, use kubectl port-forward.

**Documentation:** [Admin API Apache APISIX](https://apisix.apache.org/docs/apisix/latest/admin-api/)

**Main commands:**

```bash
# View routes
curl -s http://localhost:9180/apisix/admin/routes -H "X-API-Key: <CREDENTIAL_ADMIN>"

# View SSL certificates
curl -s http://localhost:9180/apisix/admin/ssls -H "X-API-Key: <CREDENTIAL_ADMIN>"

# View services
curl -s http://localhost:9180/apisix/admin/services -H "X-API-Key: <CREDENTIAL_ADMIN>"

# View upstreams
curl -s http://localhost:9180/apisix/admin/upstreams -H "X-API-Key: <CREDENTIAL_ADMIN>"

# Create a route (POST)
curl -X POST http://localhost:9180/apisix/admin/routes -H "X-API-Key: <CREDENTIAL_ADMIN>" -d '{"uris":["/test"],"name":"test-route","upstream_id":"<UPSTREAM_ID>"}'
```

**API Key**: The key defined in `gateway-apisix.yml` (`apisix.admin.credentials.admin`).

**Dashboard (deprecated):**
The APISIX dashboard existed as a separate project but is now **deprecated** and will no longer be maintained. The new dashboard will be integrated directly into APISIX.

To install the old interface (not recommended):
```bash
helm install apisix-dashboard apisix/apisix-dashboard -n kube-gateway
```

> **Important**: Do not mix Dashboard usage with APISIX Ingress Controller. See [Troubleshooting](https://apisix.apache.org/docs/ingress-controller/next/reference/apisix-ingress-controller/configuration-troubleshoot/)

### Legacy Ingress Compatibility

APISIX Ingress Controller automatically creates an `IngressClass` named `apisix`. This IngressClass can be used on legacy Ingress resources for progressive migration.

**Legacy Ingress - Works:**
- Path/host routing
- TLS termination
- Basic load balancing

**Legacy Ingress - Does not work:**
- NGINX ConfigSnippets
- Specific NGINX annotations (rate limiting, IP restrictions)
- NGINX rewrite annotations

For these advanced features, use HTTPRoute or native APISIX CRDs.

### Cross-Namespace Routing

By default, the Gateway only accepts HTTPRoutes from the same namespace. To allow specific namespaces via labels:
```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        gateway: "enabled"
```

For enhanced security in production, use **ReferenceGrant** to explicitly authorize access to backend services.

> **Important - Resource creation order**
>
> The `gateway=enabled` label must be applied to the namespace **BEFORE** creating the HTTPRoute.
> If the HTTPRoute is created before the label, it won't be recognized by the Gateway.
>
> **Workaround**: If the HTTPRoute was created before the label, delete and recreate the HTTPRoute:
> ```bash
> kubectl delete httproute <ROUTE_NAME> -n <NAMESPACE>
> kubectl apply -f <httproute-file>
> ```
>
> This behavior is expected according to the Gateway API specification.
> See [Issue #2727](https://github.com/apache/apisix-ingress-controller/issues/2727) for more details.

### Recommended Architecture

This section describes the recommended architecture for APISIX Gateway API with TLS, allowing to keep a minimum of resources in the application namespace.

#### Principle

For a clean and centralized architecture:
- The **Gateway** with TLS and **GatewayProxy** are created in the infrastructure namespace (`kube-gateway`)
- Only **HTTPRoutes** are created in the application namespace (`kube-monitoring`)
- The ClusterIssuer is a cluster-wide resource (non-namespaced)

| Namespace | Resources | Reason |
|-----------|-----------|--------|
| `kube-gateway` | Gateway, GatewayProxy, GatewayClass, ClusterIssuer, Certificate | Central infrastructure |
| `kube-monitoring` | **Only HTTPRoutes** | Application only |

#### Advantages

- **GatewayProxy** stays in `kube-gateway` (no cross-namespace for admin API service)
- **Gateway** with TLS in `kube-gateway` with `allowedRoutes.namespaces.from: All` to allow HTTPRoutes from all namespaces
- **HTTPRoute** in `kube-monitoring` references the Gateway via `parentRefs` with explicit namespace
- **Certificate** created by cert-manager in `kube-gateway` (TLS Secret is in the same namespace as the Gateway)

#### Official References Summary

| Topic | Documentation |
|-------|--------------|
| allowedRoutes | [Gateway API](https://gateway-api.sigs.k8s.io/api-types/gateway/) |
| Cross-namespace routing | [Gateway API Security](https://gateway-api.sigs.k8s.io/concepts/security/) |
| ReferenceGrant | [ReferenceGrant API](https://gateway-api.sigs.k8s.io/api-types/referencegrant/) |
| APISIX cross-namespace | [APISIX Issue #2727](https://github.com/apache/apisix-ingress-controller/issues/2727) |
| cert-manager Gateway | [cert-manager Gateway](https://cert-manager.io/docs/usage/gateway/) |

### Network Prerequisites for Let's Encrypt

Some Kubernetes environments (especially with Calico as CNI) block egress traffic from pods by default. This can prevent cert-manager from resolving Let's Encrypt DNS servers and validating certificates via HTTP-01.

#### DNS Configuration

By default, CoreDNS uses the node DNS. If pods cannot resolve external domains, modify CoreDNS to forward to an external DNS:

```bash
kubectl patch configmap coredns -n kube-system --type merge -p '{"data":{"Corefile":"
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . 8.8.8.8 1.1.1.1 {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
"}}}'
```

> **Note**: This configuration allows all pods in the cluster to resolve external domains via 8.8.8.8 (Google DNS) and 1.1.1.1 (Cloudflare DNS).

#### NetworkPolicy for DNS

If even after the DNS forward configuration the resolutions fail, it may be necessary to explicitly allow egress traffic from CoreDNS:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-coredns-egress
  namespace: kube-system
spec:
  podSelector:
    matchLabels:
      k8s-app: kube-dns
  policyTypes:
    - Egress
  egress:
    - {}
EOF
```

This policy allows all egress traffic from CoreDNS pods. In production, it is recommended to restrict this to the necessary ports and destinations (UDP/TCP port 53 to external DNS).

### Using an External Certificate

To use an existing TLS certificate (not managed by cert-manager), simply:
1. Create the TLS Secret manually
2. Reference it in the Gateway

```bash
# Create the TLS secret
kubectl create secret tls grafana-tls \
  --cert=path/to/certificate.crt \
  --key=path/to/key.key \
  -n kube-gateway
```

```yaml
# Reference in the Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-external-tls
  namespace: kube-gateway
spec:
  gatewayClassName: apisix
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: grafana.famille-paquin.fr
      tls:
        mode: Terminate
        certificateRefs:
          - name: grafana-tls
            kind: Secret
```

> **Note**: With Gateway API, it is NOT necessary to create an `ApisixTls`. ApisixTls is only required for legacy Ingress or ApisixRoute resources.

### Wildcard Certificate

A wildcard certificate allows managing a single certificate for all subdomains of a parent domain (e.g., `*.famille-paquin.fr`).

#### ⚠️ Important - Let's Encrypt Limitation

**HTTP-01 does NOT support wildcard certificates.**

| Challenge | Wildcard supported? |
|-----------|-------------------|
| HTTP-01 | ❌ No |
| DNS-01 | ✅ Yes |

To obtain a wildcard certificate with Let's Encrypt, use the **DNS-01** challenge.

#### Example with DNS-01 (Cloudflare)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-dns01
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@famille-paquin.fr
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-famille-paquin
  namespace: kube-gateway
spec:
  secretName: wildcard-famille-paquin-tls
  dnsNames:
    - "*.famille-paquin.fr"
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod-dns01
```

#### Correspondence Table

| Certificate dnsNames | Listener hostname | Works? |
|----------------|--------------|------------|
| `*.famille-paquin.fr` | `*.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `grafana.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `prometheus.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `other-domain.fr` | ❌ |
| `*.famille-paquin.fr` | (empty/null) | ❌ |

> **Note**: With Gateway API, each listener must have an explicit hostname. Wildcard matching works if the requested hostname is a subdomain of the wildcard.
