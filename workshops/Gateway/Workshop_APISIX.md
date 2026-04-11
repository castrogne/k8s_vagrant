# Workshop APISIX - Accès Grafana via Gateway API

## Introduction

APISIX est une gateway API cloud-native qui utilise le standard Kubernetes **Gateway API** pour gérer le routage.

### Architecture simplifiée

```
                    ┌──────────────────────────────────────────────┐
                    │      KUBERNETES (Gateway API)                │
                    │                                              │
   [Navigateur] ──▶ │  ┌─────── Gateway ───────┐                   │
   ou curl          │  │  (entry point)        │                   │
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

### Définitions

| Zone | Description |
|------|-------------|
| **Haut : Kubernetes** | Ressources standardisées Gateway API (Gateway, HTTPRoute, Certificate) |
| **Bas : APISIX** | Implémentation interne (GatewayProxy, routes APISIX, SSL) |

### Composants

| Ressource | Type | Rôle |
|----------|------|------|
| GatewayClass | K8s Standard | Définit le controller APISIX |
| Gateway | K8s Standard | Point d'entrée (http/https) |
| HTTPRoute | K8s Standard | Règles de routage |
| Certificate | cert-manager | Demande de certificat TLS |
| GatewayProxy | APISIX | Configuration vers Admin API |
| APISIX Routes | Interne | Routes dans APISIX |

---

## Objectif

Mettre en place APISIX comme Ingress/Gateway controller et exposer Grafana via un HTTPRoute.

## Prérequis

- Cluster Kubernetes fonctionnel
- Helm installé
- `kubectl` configuré
- kube-prometheus-stack installé et fonctionnel (namespace kube-monitoring)

## Fichiers de configuration

| Fichier | Rôle |
|---------|------|
| `helm/apisix/gateway-apisix.yml` | Configuration du proxy APISIX |
| `helm/apisix/ingress-controller-apisix.yml` | Configuration de l'Ingress Controller |

## Architecture cible

```
Client → APISIX Gateway → HTTPRoute → prometheus-grafana:80
                                (kube-monitoring)
```

## Étapes

### 1. Ajouter le repository APISIX

```bash
helm repo add apisix https://charts.apiseven.com
helm repo update
```

### 2. Installer APISIX

**Prérequis** : Modifier les credentials dans les fichiers values avant installation :
- `scripts/helm/apisix/gateway-apisix.yml` : remplacer `<CREDENTIAL_ADMIN>` et `<CREDENTIAL_VIEWER>`
- `scripts/helm/apisix/ingress-controller-apisix.yml` : remplacer `<CREDENTIAL_ADMIN>` (doit être identique à celui de gateway-apisix.yml)

> **Important** : Toutes les occurrences de `<CREDENTIAL_ADMIN>` (dans `gateway-apisix.yml`, `ingress-controller-apisix.yml`, et le GatewayProxy ci-dessous) doivent utiliser la **même valeur**.

> **Note réseau** : Le CIDR des pods Kubernetes doit être ajouté à `allow` pour que l'Ingress Controller puisse communiquer avec l'admin API d'APISIX.
> Pour trouver le CIDR : `kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'`

**Important** : Ne pas commiter les credentials réels dans git.

```bash
helm -n kube-gateway upgrade --install apisix apisix/apisix --version 2.13.0 -f helm/apisix/gateway-apisix.yml
```

### 3. Vérifier l'installation

```bash
kubectl -n kube-gateway get pods
kubectl -n kube-gateway get svc
```

### 4. Créer le GatewayProxy

Le GatewayProxy définit la configuration de connexion entre l'Ingress Controller et APISIX. Il doit être créé **après** APISIX et **avant** l'Ingress Controller.

**Documentation :** [Gateway API Concepts](https://apisix.apache.org/docs/ingress-controller/concepts/gateway-api-apisix/)

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

### 5. Installer l'APISIX Ingress Controller

L'Ingress Controller gère les ressources Gateway API (HTTPRoute, etc.) et crée automatiquement les CRDs Gateway API.

```bash
helm -n kube-gateway upgrade --install apisix-ingress-controller apisix/apisix-ingress-controller --version 1.1.2 -f helm/apisix/ingress-controller-apisix.yml
```

### 6. Créer le GatewayClass

Le GatewayClass doit être créé manuellement. Il indique à APISIX de gérer cette classe.

**Documentation :** [APISIX Gateway API Examples](https://apisix.apache.org/docs/ingress-controller/reference/apisix-ingress-controller/examples/)

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

### 7. Créer le Gateway (gw-http)

Représente le point d'entrée du trafic.

**Prérequis :** Ajouter le label `gateway=enabled` sur les namespaces contenant des HTTPRoutes :
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

### 8. Vérifier le Gateway

```bash
kubectl get gateway -n kube-gateway
```

### 9. Identifier le service APISIX Gateway

```bash
kubectl -n kube-gateway get svc
```

**Services attendus :**
- `apisix-gateway` : Point d'entrée du trafic (NodePort ou LoadBalancer)
- `apisix-admin` : API d'administration APISIX (ClusterIP)

**URL d'accès :** `http://<NODE_IP>:<NODE_PORT>/`

### 10. Créer le HTTPRoute (hr-grafana)

Le HTTPRoute est créé dans le namespace de l'application (kube-monitoring) et référence le Gateway (kube-gateway).

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

**Notes :**
- `hostnames` doit correspondre à une entrée DNS ou être ajouté dans `/etc/hosts`
- Pour une route par path sans hostname, retirer la section `hostnames`

### 11. Installer cert-manager et créer le ClusterIssuer

cert-manager gère les certificats TLS via Let's Encrypt.

**Prérequis** : Modifier `<EMAIL>` avec une adresse email valide pour Let's Encrypt.

**Note** : SSL est désactivé par défaut dans le chart APISIX. Voir [values.yaml APISIX](https://github.com/apache/apisix-helm-chart/blob/master/charts/apisix/values.yaml#L229) (`apisix.ssl.enabled`).

**Installation en 2 étapes** (CRDs puis Helm) :

```bash
# Étape 1 : Installer les CRDs cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml

# Étape 2 : Installer cert-manager SANS les CRDs
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace kube-gateway \
  --version v1.13.1 \
  --set crds.enabled=false \
  --set "extraArgs={--feature-gates=ExperimentalGatewayAPISupport=true}"
```

> **Note** : Cette installation en 2 étapes est nécessaire pour éviter les timeouts. Les CRDs sont volumineuses et l'installation peut échouer si on essaie de les installer en même temps que cert-manager.

#### ClusterIssuer avec gatewayHTTPRoute

Pour le HTTP-01 challenge avec Gateway API, utiliser `gatewayHTTPRoute` au lieu de `ingress`.

**Documentation** : [cert-manager Gateway API](https://cert-manager.io/docs/usage/gateway/)

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
> **Note** : Le challenge HTTP-01 nécessite que le port 80 soit accessible publiquement pour la validation du certificat.

> **Important** : cert-manager nécessite l'activation du feature gate `ExperimentalGatewayAPISupport=true` pour supporter Gateway API.
> Voir [cert-manager Gateway API documentation](https://cert-manager.io/docs/usage/gateway/)

> **Note sur l'architecture** : Pour une architecture propre avec un minimum de ressources dans le namespace applicatif (`kube-monitoring`), le Gateway est créé dans `kube-gateway` avec `allowedRoutes.namespaces.from: All` pour autoriser les HTTPRoutes de tous les namespaces. Voir la section [Architecture recommandée](#architecture-recommandée) pour plus de détails.


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

## Notes

### Admin API APISIX

L'Admin API permet de gérer APISIX en ligne de commande. C'est l'équivalent backend du Dashboard (qui est **déprécié**).

**Port-forward vers l'Admin API:**
```bash
kubectl -n kube-gateway port-forward svc/apisix-admin 9180:9180 &
```

> **Note**: Pour accéder depuis l'extérieur du cluster, utiliser kubectl port-forward.

**Documentation:** [Admin API Apache APISIX](https://apisix.apache.org/docs/apisix/latest/admin-api/)

**Commandes principales:**

```bash
# Voir les routes
curl -s http://localhost:9180/apisix/admin/routes -H "X-API-Key: <CREDENTIAL_ADMIN>"

# Voir les certificats SSL
curl -s http://localhost:9180/apisix/admin/ssls -H "X-API-Key: <CREDENTIAL_ADMIN>"

# Voir les services
curl -s http://localhost:9180/apisix/admin/services -H "X-API-Key: <CREDENTIAL_ADMIN>"

# Voir les upstreams
curl -s http://localhost:9180/apisix/admin/upstreams -H "X-API-Key: <CREDENTIAL_ADMIN>"

# Créer une route (POST)
curl -X POST http://localhost:9180/apisix/admin/routes -H "X-API-Key: <CREDENTIAL_ADMIN>" -d '{"uris":["/test"],"name":"test-route","upstream_id":"<UPSTREAM_ID>"}'
```

**API Key**: La clé définie dans `gateway-apisix.yml` (`apisix.admin.credentials.admin`).

**Dashboard (deprecated):**
Le dashboard APISIX existait en tant que projet séparé mais est maintenant **déprécié** et ne sera plus maintenu. Le nouveau dashboard sera intégré directement dans APISIX.

Pour installer l'ancienne interface (non recommandé):
```bash
helm install apisix-dashboard apisix/apisix-dashboard -n kube-gateway
```

> **Important**: Ne pas mélanger l'usage du Dashboard avec l'APISIX Ingress Controller. Voir [Troubleshooting](https://apisix.apache.org/docs/ingress-controller/next/reference/apisix-ingress-controller/configuration-troubleshoot/)

### Compatibilité Ingress Legacy

APISIX Ingress Controller crée automatiquement un `IngressClass` nommé `apisix`. Ce IngressClass peut être utilisé sur des ressources Ingress legacy pour une migration progressive.

**Ingress legacy - Fonctionne :**
- Routing par path/host
- TLS termination
- Load balancing basique

**Ingress legacy - Ne fonctionne pas :**
- ConfigSnippets NGINX
- Annotations NGINX spécifiques (rate limiting, IP restrictions)
- Rewrite annotations NGINX

Pour ces fonctionnalités avancées, utiliser HTTPRoute ou les CRDs APISIX natives.

### Cross-Namespace Routing

Par défaut, le Gateway n'accepte que les HTTPRoutes du même namespace. Pour autoriser des namespaces spécifiques via labels :
```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        gateway: "enabled"
```

Pour une sécurité renforcée en production, utiliser **ReferenceGrant** pour autoriser explicitement l'accès aux services backend.

> **Important - Ordre de création des ressources**
>
> Le label `gateway=enabled` doit être appliqué au namespace **AVANT** de créer le HTTPRoute.
> Si le HTTPRoute est créé avant le label, il ne sera pas reconnu par le Gateway.
>
> **Workaround** : Si le HTTPRoute a été créé avant le label, supprimer et recréer le HTTPRoute :
> ```bash
> kubectl delete httproute <ROUTE_NAME> -n <NAMESPACE>
> kubectl apply -f <fichier-httproute>
> ```
>
> Ce comportement est attendu selon la spécification Gateway API.
> Voir [Issue #2727](https://github.com/apache/apisix-ingress-controller/issues/2727) pour plus de détails.

### Architecture recommandée

Cette section décrit l'architecture recommandée pour APISIX Gateway API avec TLS, permettant de garder un minimum de ressources dans le namespace applicatif.

#### Principe

Pour une architecture propre et centralisée :
- Le **Gateway** avec TLS et le **GatewayProxy** sont créés dans le namespace d'infrastructure (`kube-gateway`)
- Seuls les **HTTPRoutes** sont créés dans le namespace applicatif (`kube-monitoring`)
- Le ClusterIssuer est un ressource cluster-wide (non-namespaced)

| Namespace | Ressources | Raison |
|-----------|-----------|--------|
| `kube-gateway` | Gateway, GatewayProxy, GatewayClass, ClusterIssuer, Certificate | Infrastructure centrale |
| `kube-monitoring` | **Uniquement HTTPRoutes** | Application uniquement |

#### Avantages

- **GatewayProxy** reste dans `kube-gateway` (pas de cross-namespace pour le service admin API)
- **Gateway** avec TLS dans `kube-gateway` avec `allowedRoutes.namespaces.from: All` pour autoriser les HTTPRoutes de tous les namespaces
- **HTTPRoute** dans `kube-monitoring` référence le Gateway via `parentRefs` avec le namespace explicite
- **Certificate** créé par cert-manager dans `kube-gateway` (le Secret TLS est dans le même namespace que le Gateway)

#### Résumé des références officielles

| Sujet | Documentation |
|-------|--------------|
| allowedRoutes | [Gateway API](https://gateway-api.sigs.k8s.io/api-types/gateway/) |
| Cross-namespace routing | [Gateway API Security](https://gateway-api.sigs.k8s.io/concepts/security/) |
| ReferenceGrant | [ReferenceGrant API](https://gateway-api.sigs.k8s.io/api-types/referencegrant/) |
| APISIX cross-namespace | [APISIX Issue #2727](https://github.com/apache/apisix-ingress-controller/issues/2727) |
| cert-manager Gateway | [cert-manager Gateway](https://cert-manager.io/docs/usage/gateway/) |

### Prérequis réseau pour Let's Encrypt

Certains environnements Kubernetes (notamment avec Calico comme CNI) bloquent le trafic egress des pods par défaut. Cela peut empêcher cert-manager de résoudre les serveurs DNS de Let's Encrypt et de valider les certificats via HTTP-01.

#### Configuration du DNS

Par défaut, CoreDNS utilise le DNS des nodes. Si les pods ne peuvent pas résoudre les domaines externes, modifier CoreDNS pour forwarder vers un DNS externe :

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

> **Note** : Cette configuration permet à tous les pods du cluster de résoudre les domaines externes via 8.8.8.8 (Google DNS) et 1.1.1.1 (Cloudflare DNS).

#### NetworkPolicy pour le DNS

Si même après la configuration du DNS forward, les résolutions échouent, il peut être nécessaire d'autoriser explicitement le trafic egress depuis CoreDNS :

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

Cette politique autorise tout le trafic egress depuis les pods CoreDNS. En production, il est recommandé de restreindre cela aux ports et destinations nécessaires (UDP/TCP port 53 vers les DNS externes).

### Utiliser un certificat externe

Pour utiliser un certificat TLS déjà existant (non géré par cert-manager), il suffit de :
1. Créer le Secret TLS manuellement
2. Le référencer dans le Gateway

```bash
# Créer le secret TLS
kubectl create secret tls grafana-tls \
  --cert=chemin/vers/certificat.crt \
  --key=chemin/vers/clef.key \
  -n kube-gateway
```

```yaml
# Référencer dans le Gateway
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

> **Note**: Avec Gateway API, il n'est PAS nécessaire de créer un `ApisixTls`. L'ApisixTls n'est requis que pour les ressources Ingress ou ApisixRoute legacy.

### Wildcard Certificate

Un wildcard certificate permet de gérer un seul certificat pour tous les sous-domaines d'un domaine parent (ex: `*.famille-paquin.fr`).

#### ⚠️ Important - Limitation Let's Encrypt

**HTTP-01 ne supporte PAS les wildcard certificates.**

| Challenge | Wildcard supporté ? |
|-----------|-------------------|
| HTTP-01 | ❌ Non |
| DNS-01 | ✅ Oui |

Pour obtenir un wildcard certificate avec Let's Encrypt, il faut utiliser le challenge **DNS-01**.

#### Exemple avec DNS-01 (Cloudflare)

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

#### Tableau de correspondance

| Certificate dnsNames | Listener hostname | Fonctionne ? |
|----------------|--------------|------------|
| `*.famille-paquin.fr` | `*.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `grafana.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `prometheus.famille-paquin.fr` | ✅ |
| `*.famille-paquin.fr` | `autre-domaine.fr` | ❌ |
| `*.famille-paquin.fr` | (vide/null) | ❌ |

> **Note**: Avec Gateway API, chaque listener doit avoir un hostname explicite. Le wildcard matching fonctionne si le hostname demandé est un sous-domaine du wildcard.
