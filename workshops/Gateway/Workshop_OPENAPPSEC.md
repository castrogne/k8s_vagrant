# Workshop OPENAPPSEC - ML-based WAF with APISIX

> **Note**: I failed using OpenAppsec with APISIX in API Gateway. Policies are not detected... Openappsec is in beta with many issues, I shall wait a stable version... I tied V1Beta1 with no success, didn't tries V1beta2.

## Introduction

open-appsec is a **machine learning-based Web Application Firewall** that integrates with APISIX as a sidecar container.

### Simplified Architecture

```
                     ┌──────────────────────────────────────────────┐
                     │      KUBERNETES (Gateway API)                │
                     │                                              │
    [Browser] ──▶    │  ┌─────── Gateway ───────┐                   │
    or curl          │  │  (entry point)        │                   │
                     │  │       │               │                   │
                     │  │  HTTPRoute ────► Service                  │
                     │  └──────────────────────┘                    │
                     └──────────────────────────────────────────────┘
                               │
                               │ APISIX Ingress Controller
                               ▼
                     ┌──────────────────────────────────────────────┐
                     │         APISIX + open-appsec                 │
                     │                                              │
                     │  GatewayProxy → Routes / SSL / Upstreams     │
                     │                           ◀──► etcd          │
                     │                                              │
                     │  ┌────────────────────────────────────────┐  │
                     │  │  open-appsec-agent (sidecar)           │  │
                     │  │  - ML-based threat detection           │  │
                     │  │  - Zero-day protection                 │  │
                     │  │  - Learns from traffic patterns        │  │
                     │  └────────────────────────────────────────┘  │
                     └──────────────────────────────────────────────┘
```

### Definitions

| Zone | Description |
|------|-------------|
| **Kubernetes** | Standardized Gateway API resources (Gateway, HTTPRoute) |
| **APISIX + open-appsec** | Internal implementation with ML-based WAF |

### Components

| Resource | Type | Role |
|----------|------|------|
| GatewayClass | K8s Standard | Defines the APISIX controller |
| Gateway | K8s Standard | Entry point (http/https) |
| HTTPRoute | K8s Standard | Routing rules |
| GatewayProxy | APISIX | Admin API configuration |
| open-appsec-agent | Sidecar | ML-based WAF engine |

---

## Objective

Deploy open-appsec with APISIX as an ML-based WAF solution, replacing the Coraza rule-based WAF.

## Prerequisites

- Working Kubernetes cluster
- Helm installed
- `kubectl` configured
- kube-prometheus-stack installed (namespace kube-monitoring)
- **Important**: This replaces the existing APISIX deployment

## Configuration Files

| File | Role |
|------|------|
| `scripts/helm/openappsec/values.yml` | open-appsec + APISIX configuration |

---

## Steps

### 1. Download Helm Chart

```bash
wget https://downloads.openappsec.io/packages/helm-charts/apisix/open-appsec-k8s-apisix-latest.tgz
```

### 2. Configuration File

Use the configuration file: `scripts/helm/openappsec/values.yml`

**Prerequisites**: Modify the placeholders before installation:
- `<CREDENTIAL_ADMIN>` - Admin API key
- `<CREDENTIAL_VIEWER>` - Viewer API key
- `<YOUR_EMAIL>` - Your email address

### 3. Install open-appsec with APISIX

```bash
helm install open-appsec-k8s-apisix-latest.tgz \
  --name-template=apisix \
  -n kube-gateway \
  --create-namespace \
  -f scripts/helm/openappsec/values.yml
```

> **Important**: Do not commit real credentials to git.

### 4. Verify Installation

```bash
kubectl -n kube-gateway get pods
kubectl -n kube-gateway get svc
kubectl -n kube-gateway get ingressclass
```

**Expected pods:**
- `apisix-etcd-*`
- `apisix-apisix-gateway-*` (with open-appsec sidecar)
- `apisix-apisix-ingress-controller-*`
- `apisix-open-appsec-learning-*`
- `apisix-open-appsec-shared-storage-*`

### 5. Create GatewayProxy

The GatewayProxy defines the connection configuration between the Ingress Controller and APISIX.

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

### 6. Create GatewayClass

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: appsec-apisix
spec:
  controllerName: apisix.apache.org/apisix-ingress-controller
EOF
```

### 7. Create Gateway

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-http
  namespace: kube-gateway
spec:
  gatewayClassName: appsec-apisix
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

### 8. Create HTTPRoute (Simple Example)

For detailed HTTPRoute configuration, see **Workshop_APISIX.md**.

```bash
# Label the namespace to allow routes
kubectl label namespace kube-monitoring gateway=enabled

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

---

## open-appsec Configuration

### Default Mode: detect-learn

By default, open-appsec runs in **detect-learn** mode:
- Logs threats but doesn't block
- Learns from traffic to identify normal vs malicious
- Recommended for initial deployment

### Switch to Prevent Mode

After learning period, switch to blocking mode:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: openappsec.io/v1beta1
kind: Policy
metadata:
  name: open-appsec-best-practice-policy
  namespace: kube-gateway
spec:
  default:
    mode: prevent-learn
EOF
```

### Available Modes

| Mode | Description |
|------|-------------|
| `detect` | Log only, no learning |
| `detect-learn` | Log + ML learning (default) |
| `prevent` | Block without learning |
| `prevent-learn` | Block + ML learning |

---

## Testing

### Test 1: SQL Injection

```bash
curl -i "http://<NODE_IP>:30080?q=1' OR '1'='1"
```

**Expected (in prevent mode):** HTTP/1.1 403 Forbidden

**Expected (in detect-learn mode):** HTTP/1.1 200 OK (logged)

### Test 2: XSS Attack

```bash
curl -i "http://<NODE_IP>:30080?q=<script>alert(1)</script>"
```

### Test 3: Check Logs

```bash
kubectl logs -n kube-gateway -l app=open-appsec -c open-appsec -f
```

---

## Comparison with Coraza

| Feature | Coraza | open-appsec |
|---------|--------|-------------|
| **Detection Type** | Signature-based | Machine Learning |
| **Zero-day Protection** | Limited | Yes |
| **Setup Complexity** | Easy (built-in) | Medium (sidecar) |
| **Learning Capability** | No | Yes |
| **Bot/DDoS Mitigation** | Basic (rate limit) | Advanced |

---

## Troubleshooting

### Check open-appsec Status

```bash
kubectl get policy -n kube-gateway
kubectl get policyactivation -n kube-gateway
```

### View Events

```bash
kubectl describe policy -n kube-gateway open-appsec-best-practice-policy
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Requests not blocked | Check mode is `prevent*` |
| No learning | Wait for traffic to accumulate |
| Pods not ready | Check logs: `kubectl logs -n kube-gateway <pod>` |

---

## Notes

For detailed HTTPRoute, Gateway, TLS, and rate limiting configurations, see **Workshop_APISIX.md**.

### Access URL

**HTTP:** `http://<NODE_IP>:30080/`

**HTTPS:** `https://<NODE_IP>:30443/` (requires TLS configuration)
