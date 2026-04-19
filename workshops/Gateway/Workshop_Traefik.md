# Workshop Traefik - Grafana Access via Gateway API

## Introduction

Traefik is a cloud-native API gateway that uses the Kubernetes **Gateway API** standard for routing, combined with **CrowdSec** for behavior-based WAF protection.

### Simplified Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │      KUBERNETES (Gateway API)                │
                    │                                              │
   [Browser] ──▶    │  ┌─────── Gateway ───────┐                   │
   or curl          │  │  (entry point)        │                   │
                    │  │       │               │                   │
                    │  │  HTTPRoute ────► Service                  │
                    │  │       │                                   │
                    │  └──────────────────────┘                    │
                    └──────────────────────────────────────────────┘
                              │
                              │ Traefik Ingress Controller
                              ▼
                    ┌──────────────────────────────────────────────┐
                    │         Traefik (Gateway)                    │
                    │                                              │
                    │  Gateway → Routes / Middleware               │
                    │                                              │
                    └──────────────────────────────────────────────┘
                              │
                              │ Plugin (Bouncer)
                              ▼
                    ┌──────────────────────────────────────────────┐
                    │         CrowdSec (WAF)                       │
                    │                                              │
                    │  AppSec → Behavior Detection → Decisions     │
                    │  LAPI → Bouncer → Block/Allow                │
                    └──────────────────────────────────────────────┘
```

### Definitions

| Zone | Description |
|------|-------------|
| **Top: Kubernetes** | Standardized Gateway API resources (Gateway, HTTPRoute) |
| **Middle: Traefik** | Gateway implementation with Middleware |
| **Bottom: CrowdSec** | Security engine with behavior-based WAF |

### Components

| Resource | Type | Role |
|----------|------|------|
| GatewayClass | K8s Standard | Defines the Traefik controller |
| Gateway | K8s Standard | Entry point (http/https) |
| HTTPRoute | K8s Standard | Routing rules |
| Middleware | Traefik | Plugin for security (bouncer, rate limiting) |
| CrowdSec | Security Engine | Behavior-based detection |
| AppSec | CrowdSec | WAF component |

---

## Objective

Deploy Traefik as a Gateway API controller with CrowdSec WAF, and expose Grafana via an HTTPRoute.

## Prerequisites

- Working Kubernetes cluster
- Helm installed
- `kubectl` configured
- kube-prometheus-stack installed and working (namespace kube-monitoring)

## Configuration Files

| File | Role |
|------|------|
| `helm/traefik/gateway-traefik.yml` | Traefik Gateway configuration |
| `helm/traefik/crowdsec.yml` | CrowdSec Security Engine configuration |

## Target Architecture

```
Client → Traefik Gateway → HTTPRoute → prometheus-grafana:80
                       → Middleware (Bouncer) → CrowdSec
                                 (kube-monitoring)
```

---

## Steps

### 1. Add Repositories

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm repo update
```

### 2. Install Traefik CRDs

Traefik CRDs provide custom resource types (Middleware, IngressRoute) required for configuration.

```bash
helm upgrade --install traefik-crds traefik/traefik-crds \
  -n kube-gateway \
  --create-namespace
```

### 3. Install CrowdSec (first)

**Prerequisites**: None required for basic standalone installation.

> **Optional**: Get a registration token from [CrowdSec Console](https://www.crowdsec.net/) (free account) only if you want the online dashboard.

**Installation**:

```bash
kubectl create ns crowdsec
helm -n crowdsec upgrade --install crowdsec crowdsec/crowdsec --version 0.23.0 -f helm/traefik/crowdsec.yml
```

**Generate Bouncer Key** (required for Traefik):

```bash
# Run this AFTER CrowdSec is installed
kubectl -n crowdsec exec -it crowdsec-lapi-0 -- cscli bouncer add traefik
```

**Output example**:
```
API key for 'traefik':
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

> **Important**: Copy this key - you need it for the Traefik Middleware (Section 12).

### 4. Install Traefik

> **Note**: The bouncer key is NOT set in the values file. It's configured in the Middleware (Section 12) after installation.

```bash
kubectl create ns kube-gateway
helm -n kube-gateway upgrade --install traefik traefik/traefik --version 39.0.5 -f helm/traefik/gateway-traefik.yml
```

### 5. Verify Installation

```bash
kubectl -n kube-gateway get pods
kubectl -n kube-gateway get svc
kubectl -n crowdsec get pods
kubectl -n crowdsec get svc
```

### 6. Create GatewayClass

The GatewayClass must be created manually. It tells Traefik to handle this class.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
EOF
```

### 7. Create Gateway (gw-http)

Represents the traffic entry point.

> **Note**: Add the `gateway=enabled` label to namespaces containing HTTPRoutes:
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
  gatewayClassName: traefik
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

### 9. Identify Traefik Gateway Service

```bash
kubectl -n kube-gateway get svc
```

**Expected services:**
- `traefik`: Traffic entry point (NodePort or LoadBalancer)

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

---

## 11: Rate Limiting with Traefik

### 11.1 Introduction

Rate limiting allows controlling the number of requests allowed to a service. This is useful for:
- Protecting against abuse and DDoS attacks
- Implementing API monetization (per-request quotas)
- Ensuring quality of service (QoS)
- Extreme limits like "1 request per day"

**Key Features:**
- Built-in (no plugin needed)
- Supports periods: seconds, minutes, hours, days
- Distributed rate limiting via Redis (optional)

### 11.2 Built-in Rate Limiting

Traefik v3 includes built-in rate limiting via `RateLimit` middleware. The key parameter is `period` which supports various time units:

| Period | Meaning | Use Case |
|--------|---------|----------|
| `1s` | Per second | High-traffic APIs |
| `1m` | Per minute | Moderate usage |
| `1h` | Per hour | Limited APIs |
| `1d` or `24h` | Per day | Daily quotas |

**Configuration Examples:**

| Use Case | average | period | burst |
|---------|---------|-------|-------:|
| 100 req/s | 100 | 1s | 50 |
| 1000 req/min | 1000 | 1m | 100 |
| 100 req/h | 100 | 1h | 20 |
| 1 req/day | 1 | 1d | 0 |

#### Example: 1000 requests per minute

```bash
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit-per-minute
  namespace: kube-gateway
spec:
  rateLimit:
    average: 1000
    burst: 100
    period: 1m
EOF
```

#### Example: 1 request per day (extreme limit)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit-per-day
  namespace: kube-gateway
spec:
  rateLimit:
    average: 1
    burst: 0
    period: 1d
EOF
```

### 11.3 Associate HTTPRoute with Rate Limiting

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-rate-limited
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
            value: /api/
      backendRefs:
        - name: prometheus-grafana
          port: 80
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: rate-limiter
EOF
```

---

## 12: CrowdSec WAF Integration

### 12.1 Introduction

CrowdSec provides **behavior-based WAF protection** that differs from signature-based WAFs:

| Aspect | Traditional WAF | CrowdSec |
|--------|------------------|----------|
| **Detection** | Signatures | Behavior + Scenarios |
| **Adaptive attacks** | ❌ Limited | ✅ Yes |
| **Bot protection** | ❌ No | ✅ Yes |
| **Community intel** | ❌ No | ✅ Yes |

### Architecture

```
[Client] --> [Traefik Gateway] --> [Bouncer Middleware] --> [CrowdSec LAPI]
                |                        |                        |
                |                   Inspects:                 |
                |                   - IP decisions            |
                |                   - AppSec WAF               |
                +-------------- 403 Forbidden (blocked)
```

### 12.2 Prerequisites

Ensure CrowdSec is installed and running (Section 3-4).

The bouncer key must match between Traefik values and CrowdSec configuration.

### 12.3 Create Bouncer Middleware

```bash
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: crowdsec-bouncer
  namespace: kube-gateway
spec:
  plugin:
    crowdsec-bouncer-traefik-plugin:
      enabled: true
      crowdsecMode: stream
      crowdsecLapiScheme: http
      crowdsecLapiHost: crowdsec-lapi.crowdsec.svc.cluster.local:8080
      crowdsecLapiKey: <BOUNCER_KEY>
      crowdsecAppsecEnabled: true
      crowdsecAppsecHost: crowdsec-appsec-service.crowdsec.svc.cluster.local:7422
      crowdsecAppsecFailureBlock: true
      crowdsecAppsecUnreachableBlock: true
EOF
```

> **Important**: Replace `<BOUNCER_KEY>` with your actual bouncer key.

### 12.4 Associate HTTPRoute with WAF

Add the CrowdSec bouncer middleware to an existing HTTPRoute:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-waf
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-http
      namespace: kube-gateway
  hostnames:
    - "<DOMAIN>"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: prometheus-grafana
          port: 80
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: crowdsec-bouncer
EOF
```

> **Note**: Replace `<DOMAIN>` with your actual domain.

---

## 13: Testing WAF Protection

### 13.1 Test Signatures

#### Test 1: SQL Injection

```bash
# URL encoded (recommended)
curl -ki "http://<DOMAIN>?q=1%27%20OR%20%271%27=%271"
```

**Expected Response:**
```
HTTP/1.1 403 Forbidden
Content-Type: text/plain
x-crowdsec-action: ban
x-crowdsec-blocked: true
```

#### Test 2: XSS Attack

```bash
curl -ki "http://<DOMAIN>?q=%3Cscript%3Ealert(1)%3C/script%3E"
```

**Expected:** HTTP/1.1 403 Forbidden

#### Test 3: Path Traversal

```bash
curl -i "http://<DOMAIN>?q=/etc/passwd"
curl -i "http://<DOMAIN>?q=../../etc/passwd"
```

### 13.2 Test Behavior Scenarios

#### Test 4: Aggressive Crawling

```bash
# Rapid requests to different endpoints
for i in $(seq 1 10); do
  curl -s "http://<DOMAIN>/page$i" > /dev/null
done
```

**Expected:** After 5+ rapid requests, the IP should be banned for aggressive crawling.

#### Test 5: Probing Detection

```bash
# Different attack patterns in rapid succession
curl -s "http://<DOMAIN>/admin.php"
curl -s "http://<DOMAIN>/login?a='"
curl -s "http://<DOMAIN>/user?id=1'"
curl -s "http://<DOMAIN>/search?q=--"
curl -s "http://<DOMAIN>/api?cmd=whoami"
```

**Expected:** Blocked after detecting probing behavior.

### 13.3 Test Normal Request (should pass)

```bash
curl -i "http://<DOMAIN>?q=normal+query"
```

**Expected:** HTTP/1.1 200 OK

---

## 14: CrowdSec Scenarios Reference

### Available Scenarios

| Scenario | Description |
|----------|-------------|
| `http-crawl-non_statics` | Aggressive crawling |
| `http-probing` | Rapid scanning/probing |
| `http-path-traversal-probing` | Path traversal attempts |
| `http-sqli-probing` | SQL injection probing |
| `http-xss-probing` | XSS probing |
| `http-backdoors-attempt` | Known backdoor files |
| `http-admin-interface-probing` | Admin panel discovery |
| `http-bad-user-agent` | Suspicious User-Agent |

### Enable Additional Scenarios

Update the CrowdSec agent configuration:

```bash
helm -n crowdsec upgrade --install crowdsec crowdsec/crowdsec --version 0.23.0 \
  --set "agent.env[0].name=COLLECTIONS" \
  --set "agent.env[0].value=crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/http-dos crowdsecurity/appsec-wordpress"
```

---

## 15: TLS/HTTPS with cert-manager

### 15.1 Install cert-manager

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

### 15.2 Create ClusterIssuer

Modify `<EMAIL>` with a valid email for Let's Encrypt.

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
              - name: gw-http
                namespace: kube-gateway
EOF
```

> **Important**: cert-manager requires the feature gate `ExperimentalGatewayAPISupport=true` to support Gateway API.

### 15.3 Create HTTPS Gateway

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-https
  namespace: kube-gateway
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  gatewayClassName: traefik
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
      hostname: "<DOMAIN>"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: grafana-tls
            kind: Secret
EOF
```

> **Note**: The TLS Secret will be created by cert-manager automatically.

---

## 16: Cross-Namespace Configuration

### 16.1 Architecture Overview

This workshop uses cross-namespace routing:

| Namespace | Resources | Purpose |
|-----------|-----------|----------|
| `kube-gateway` | Gateway, GatewayClass, Middleware (WAF) | Central infrastructure |
| `kube-monitoring` | HTTPRoute, Service (Grafana) | Application |

### 16.2 Gateway Configuration

The Gateway allows routes from all namespaces:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

### 16.3 Cross-Namespace Middleware

**Prerequisite**: Enable `allowCrossNamespace` in Helm values (already set in `gateway-traefik.yml`):

```yaml
providers:
  kubernetesCRD:
    allowCrossNamespace: true
```

The Middleware (WAF bouncer) is in `kube-gateway`, but can be referenced from `kube-monitoring`:

```yaml
# In kube-monitoring namespace
spec:
  parentRefs:
    - name: gw-http
      namespace: kube-gateway
  rules:
    - filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: crowdsec-bouncer
```

> **Note**: The middleware reference works because `allowCrossNamespace: true` is enabled in Traefik values.

### 16.4 HTTPRoute in Different Namespace

The HTTPRoute in `kube-monitoring` references:
- Gateway in `kube-gateway` (via `parentRefs` with namespace)
- Middleware in `kube-gateway` (via `ExtensionRef`)
- Service in `kube-monitoring` (native Gateway API)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-waf
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-http
      namespace: kube-gateway
  hostnames:
    - "<DOMAIN>"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: prometheus-grafana
          port: 80
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: crowdsec-bouncer
EOF
```

---

## 17: Troubleshooting

### Check Pods Status

```bash
kubectl -n kube-gateway get pods
kubectl -n crowdsec get pods
```

### Check Traefik Logs

```bash
kubectl logs -n kube-gateway -l app.kubernetes.io/name=traefik -f
```

### Check CrowdSec Logs

```bash
kubectl logs -n crowdsec -l app.kubernetes.io/name=crowdsec -f
```

### Check Bouncer Decisions

```bash
kubectl -n crowdsec exec -it crowdsec-lapi-<POD> -- cscli decisions list
```

### Verify Bouncer Key

```bash
kubectl -n crowdsec exec -it crowdsec-lapi-<POD> -- cscli bouncer list
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Bouncer not blocking | Check bouncer key matches in Traefik Middleware and CrowdSec |
| No AppSec detection | Verify AppSec is enabled and port 7422 is accessible |
| Gateway not ready | Check GatewayClass exists and Traefik pods are running |
| HTTPRoute not applied | Ensure namespace has `gateway=enabled` label |

### Test Bouncer Configuration

```bash
# Add a test ban
kubectl -n crowdsec exec -it crowdsec-lapi-<POD> -- cscli decisions add --ip 1.2.3.4 --duration 1h

# Test from that IP
curl -i --interface 1.2.3.4 http://<DOMAIN>/

# Remove test ban
kubectl -n crowdsec exec -it crowdsec-lapi-<POD> -- cscli decisions delete --ip 1.2.3.4
```

---

## Notes

### Cross-Namespace Routing

By default, the Gateway only accepts HTTPRoutes from namespaces with the `gateway=enabled` label. To allow all namespaces:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

### Dashboard Access

Traefik Dashboard is enabled by default at `/dashboard/` (insecure mode):

```bash
# Port-forward to dashboard
kubectl -n kube-gateway port-forward svc/traefik 9000:80 &
# Access at http://localhost:9000/dashboard/
```

### CrowdSec Console

Connect CrowdSec to the console for centralized monitoring:

```bash
# Register with token
kubectl -n crowdsec exec -it crowdsec-lapi-<POD> -- cscli console register -t <REGISTRATION_TOKEN>
```

### Metrics

Prometheus metrics are enabled. Access via:

```bash
kubectl -n kube-gateway port-forward svc/traefik 9000:80 &
# Metrics at http://localhost:9000/metrics
```

---

## Appendix A: Installation Issues & Fixes

This section documents errors encountered during installation and their solutions.

### A.1 Traefik: defaultScope Experimental Error

**Error:**
```
ERROR: The Gateway 'defaultScope' field is experimental.
Enable it by setting providers.kubernetesGateway.experimentalChannel=true
```

**Cause:** The Helm chart version 39.0.5 requires explicit opt-in for experimental Gateway API features.

**Fix:** Add `experimentalChannel: true` to the values file:

```yaml
providers:
  kubernetesGateway:
    enabled: true
    experimentalChannel: true  # Required for experimental features
```

---

### A.2 CrowdSec: Unbound PersistentVolumeClaims

**Error:**
```
Warning  FailedScheduling  0/3 nodes are available:
pod has unbound immediate PersistentVolumeClaims.
```

**Cause:** The CrowdSec chart creates PVCs but persistence was not properly configured.

**Fix:** Enable persistence with local-path storage:

```yaml
lapi:
  persistentVolume:
    config:
      enabled: true
      storageClassName: local-path
      size: 1Gi
    data:
      enabled: true
      storageClassName: local-path
      size: 1Gi
```

---

### A.3 CrowdSec: Missing Token for Auto-Registration

**Error:**
```
Error: cscli machines add: failed to load Local API:
missing token value for api.server.auto_register
```

**Cause:** The `config.yaml.local` was missing the `auto_registration` section.

**Fix:** Add auto_registration configuration:

```yaml
config:
  config.yaml.local: |
    api:
      server:
        auto_registration:
          enabled: true
          token: "${REGISTRATION_TOKEN}"  # Let chart auto-generate
          allowed_ranges:
            - "127.0.0.1/32"
            - "192.168.0.0/16"
            - "10.0.0.0/8"
            - "172.16.0.0/12"
```

> **Important:** Use the placeholder `${REGISTRATION_TOKEN}` - the chart will auto-generate and inject the same token for both LAPI and agents. Do NOT use a custom token unless you also configure agent environment variables.

---

### A.4 CrowdSec Agent: Machine Not Validated

**Error:**
```
API error: machine crowdsec-agent-xxx not validated
```

**Cause:** Agent tried to register but couldn't validate automatically.

**Fix:** This is resolved by using `${REGISTRATION_TOKEN}` placeholder (see A.3). The chart auto-generates the token and injects it into both LAPI and agent pods.

---

### A.5 CrowdSec AppSec: Missing Labels

**Error:**
```
crowdsec init: while loading acquisition config:
/etc/crowdsec/acquis.yaml: missing labels
```

**Cause:** AppSec acquisition configuration was missing required `labels` field.

**Fix:** Add `labels` and `appsec_config` to the appsec acquisitions:

```yaml
appsec:
  enabled: true
  acquisitions:
    - source: appsec
      listen_addr: "0.0.0.0:7422"
      path: /
      appsec_config: crowdsecurity/virtual-patching
      labels:
        type: appsec
```

---

### A.6 Token Summary

| Token Type | Source | Purpose |
|------------|--------|---------|
| ENROLL_KEY | CrowdSec Console (app.crowdsec.net) | Connect to online dashboard |
| BOUNCER_KEY_TRAEFIK | Custom (you generate) | Traefik queries CrowdSec decisions |
| REGISTRATION_TOKEN | Auto-generated by Helm chart | Agent auto-registration to LAPI |

---

## Appendix B: Useful Commands

### Check CrowdSec Status
```bash
kubectl -n crowdsec get pods
kubectl -n crowdsec logs crowdsec-lapi-xxx
kubectl -n crowdsec exec -it crowdsec-lapi-xxx -- cscli metrics
```

### Validate Machines
```bash
kubectl -n crowdsec exec -it crowdsec-lapi-xxx -- cscli machines list
kubectl -n crowdsec exec -it crowdsec-lapi-xxx -- cscli machines validate <machine-name>
```

### Check Bouncer
```bash
kubectl -n crowdsec exec -it crowdsec-lapi-xxx -- cscli bouncer list
kubectl -n crowdsec exec -it crowdsec-lapi-xxx -- cscli decisions list
```

---

## Appendix C: Gateway & HTTPRoute Configuration Issues

This section documents errors and solutions when configuring Gateway API with Traefik.

### C.1 Gateway: Port Mismatch with Traefik EntryPoints

**Error:**
```
ERR Gateway Not Accepted error="Cannot find entryPoint for Gateway:
no matching entryPoint for port 80 and protocol \"HTTP\""
```

**Cause:** The Gateway manifest specifies port 80, but the Traefik Helm values configure listeners on port 8000 by default.

**Fix:** Match the Gateway port to Traefik's entryPoints (8000):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-http
  namespace: kube-gateway
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      port: 8000          # Must match Traefik's web port
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
```

---

### C.2 Helm Creates Default Gateway Automatically

**Problem:** When enabling `providers.kubernetesGateway.enabled: true`, the Traefik Helm chart automatically creates:
- `GatewayClass` named `traefik`
- `Gateway` named `traefik-gateway` (port 8000)

This creates conflicts when you want to use your own manifests.

**Fix:** Disable automatic Gateway creation in Helm values:

```yaml
# Add to gateway-traefik.yml
gateway:
  enabled: false      # Disable default Gateway

gatewayClass:
  enabled: false     # Disable default GatewayClass
```

---

### C.3 Gateway Rejects Cross-Namespace Routes

**Error:** Routes from other namespaces are not attached.

**Cause:** Default Gateway uses `allowedRoutes.namespaces.from: Same` - only accepts routes from the same namespace.

**Fix:** Update Gateway to use selector-based namespace selection:

```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        gateway: "enabled"
```

Then label target namespaces:
```bash
kubectl label namespace kube-monitoring gateway=enabled
```

Or use `from: All` for simplicity:
```yaml
allowedRoutes:
  namespaces:
    from: All
```

---

## Summary: Gateway Configuration Checklist

| Check | Value |
|-------|-------|
| Gateway port | Must match Traefik's entryPoint (default: 8000) |
| allowedRoutes.namespaces | `from: All` or selector with label |
| Target namespace label | `gateway=enabled` (if using selector) |
| Helm default Gateway | Set `gateway.enabled: false` to disable |

---

## Resources

| Topic | Documentation |
|-------|--------------|
| Traefik Helm Chart | https://github.com/traefik/traefik-helm-chart |
| Traefik Gateway API | https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/ |
| CrowdSec Helm | https://github.com/crowdsecurity/helm-charts |
| CrowdSec Traefik | https://doc.crowdsec.net/docs/next/appsec/quickstart/traefik |
| Gateway API | https://gateway-api.sigs.k8s.io/ |
| cert-manager Gateway | https://cert-manager.io/docs/usage/gateway/ |

---

*Document generated: Avril 2026*
*Last updated: Avril 2026 - Added Appendix A (Installation Issues & Fixes), Appendix B (Useful Commands), and Appendix C (Gateway Configuration Issues)*