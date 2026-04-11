# Workshop APISIX - Accès Grafana via Gateway API

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

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace kube-gateway \
  --version v1.13.1 \
  --set "extraArgs={--feature-gates=ExperimentalGatewayAPISupport=true}" \
  --set crds.enabled=true
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.letsencrypt.org/directory
    email: <EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: apisix
EOF
```

> **Note** : Le challenge HTTP-01 nécessite que le port 80 soit accessible publiquement pour la validation du certificat.

> **Important** : cert-manager nécessite l'activation du feature gate `ExperimentalGatewayAPISupport=true` pour supporter Gateway API.
> Voir [cert-manager Gateway API documentation](https://cert-manager.io/docs/usage/gateway/)

#### Gateway gw-https avec listener HTTPS

**Lien doc** : [Gateway API - HTTP to HTTPS redirect](https://gateway-api.sigs.k8s.io/guides/http-redirect-rewrite/#http-to-https-redirects)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-https
  namespace: kube-monitoring
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
          from: Selector
          selector:
            matchLabels:
              gateway: "enabled"
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "grafana.local"
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway: "enabled"
      tls:
        mode: Terminate
        certificateRefs:
          name: grafana-tls
          kind: Secret
          group: ""
EOF
```

#### HTTPRoute redirect HTTP → HTTPS

**Lien doc** : [Gateway API - HTTP to HTTPS redirect](https://gateway-api.sigs.k8s.io/guides/http-redirect-rewrite/#http-to-https-redirects)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana-redirect
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-https
      namespace: kube-monitoring
      sectionName: http
  hostnames:
    - "grafana.local"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
EOF
```

#### HTTPRoute traffic HTTPS vers Grafana

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hr-grafana
  namespace: kube-monitoring
spec:
  parentRefs:
    - name: gw-https
      namespace: kube-monitoring
      sectionName: https
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

## Notes

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
