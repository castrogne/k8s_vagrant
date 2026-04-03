# Migration Ingress NGINX vers Gateway API

## Contexte

### Retrait de Ingress NGINX

- **Date de retrait** : Mars 2026
- **Action** : Plus de releases, bugfixes ou correctifs de sécurité
- **Source** : [Kubernetes Blog - Ingress NGINX Retirement](https://www.kubernetes.dev/blog/2025/11/12/ingress-nginx-retirement/)

### Solution recommandée

- **Gateway API** : Le successor officiel de Kubernetes pour le traffic management

---

## Pré-requis et contraintes

### Fonctionnalités requises

| Fonctionnalité | Priorité | Notes |
|----------------|----------|-------|
| Server/Config Snippets | Haute | Équivalent aux annotations NGINX |
| Regex sur paths | Haute | Pour matching advanced |
| IP Ban/Whitelist | Haute | Blocage par IP |
| Rate Limiting | Haute | Le plus large possible |
| Redirect 301 regex | Haute | Redirections basées sur regex |
| WAF | Haute | OWASP Core Rule Set |
| HTTPS / TLS | Haute | Let's Encrypt (cert-manager) |

### Contraintes budgétaires

- **WAF** : Privilégier une solution open-source ou gratuite
- **Infrastructure** : Cluster Kubernetes local (Vagrant/VirtualBox)

---

## Comparatif des implémentations Gateway API

### Vue d'ensemble des options

| Implémentation | WAF | Rate Limit | IP Filter | Regex | Redirect 301 | TLS/Let's Encrypt | Maintenance |
|----------------|-----|------------|-----------|-------|--------------|-------------------|-------------|
| **NGINX Gateway Fabric** | ❌ (F5 Payant) | ✅ | ✅ (snippets) | ✅ | ✅ | ✅ (cert-manager) | F5 (Commercial) |
| **Envoy Gateway** | ❌ (Tetrate Enterprise) | ✅ | ✅ | ✅ | ✅ | ✅ (cert-manager) | CNCF/Envoy |
| **APISIX** | ✅ (Coraza Gratuit) | ✅ | ✅ | ✅ | ✅ | ✅ (cert-manager) | Apache |
| **Traefik Proxy** | ⚠️ (WASM perfor. limitée) | ✅ | ✅ | ✅ | ✅ | ✅ (Let's Encrypt natif) | Traefik Labs |

### Détails par implémentation

#### 1. NGINX Gateway Fabric

**Avantages :**
- Continuité technique avec ingress-nginx
- Snippets equivalents (`SnippetsFilter` / `SnippetsPolicy`)
- Rate limiting via `RateLimitPolicy`
- Regex path (RE2)
- Moteur NGINX familier

**Inconvénients :**
- WAF nécessite NGINX App Protect (payant F5)
- Dépendance commerciale F5

**Performances :** ★★★★★

#### 2. Envoy Gateway

**Avantages :**
- Projet officiel CNCF/Envoy
- Large adoption dans service mesh (Istio)
- Bonne conformance Gateway API
- Community-driven

**Inconvénients :**
- Pas de snippets equivalents (CRD extensions complexes)
- WAF uniquement via Tetrate Enterprise (payant)
- Rate limiting global nécessite Redis

**Performances :** ★★★★☆

#### 3. Apache APISIX ★ Recommandé ★

**Avantages :**
- **WAF open-source gratuit** (Coraza natif)
- Performance **+56% vs NGINX** (58k QPS single-core)
- Hot-reload (pas de reload sur changement routes)
- 1ms sync configuration
- Rate limiting natif
- Regex path natif
- Gateway API support (beta)
- Projet Apache (maintenance active)

**Inconvénients :**
- Gateway API en beta (mais actif développement)
- Plus complexe que NGINX

**TLS / Let's Encrypt :**
- Support via cert-manager (ACME)
- Automatic certificate management
- Renewal automatique

**Performances :** ★★★★★

**WAF Coraza :**
- Moteur open-source OWASP
- Compatible ModSecurity SecLang
- Support OWASP Core Rule Set
- 23x plus performant que WASM Traefik

#### 4. Traefik Proxy

**Avantages :**
- Simple à configurer
- Large communauté
- Rate limiting natif

**Inconvénients :**
- WAF via plugin WASM (performances limitées selon retours)
- Moins performant que APISIX/NGINX

**Performances :** ★★★☆☆

---

## Benchmark comparatif (sources)

| Solution | QPS (single-core) | Notes |
|----------|------------------|-------|
| NGINX | 37,154 | Référence |
| **APISIX** | **58,080** | +56% vs NGINX |
| HAProxy | ~30,000+ | Très performant |
| Envoy | ~20,000-30,000 | Bon mais moins |
| Traefik | ~10,000 | Plus lent |

*Sources : API7.ai benchmarks, Medium benchmarks*

---

## Recommandation finale

### Choix : Apache APISIX

**Pourquoi APISIX :**

1. ✅ **WAF gratuit** - Coraza natif (autres nécessitent licence)
2. ✅ **Meilleures performances** - +56% vs NGINX
3. ✅ **Features complètes** - Rate limit, IP filter, regex, redirect, TLS
4. ✅ **Hot-reload** - Pas de downtime lors des changements
5. ✅ **Projet Apache** - Maintenance active, pas de vendor lock-in
6. ✅ **Gateway API** - Support en développement actif
7. ✅ **Let's Encrypt** - Support via cert-manager

### Alternatives

| Si... | Choix alternatif |
|--------|------------------|
| Tu veux absoluement le support Gateway API GA | NGINX Gateway Fabric |
| Tu as déjà Istio et veux uniformiser | Envoy Gateway |
| Tu veux simplicité maximale | Traefik Proxy (avec WAF limité) |

---

## Prochaines étapes

1. Tester APISIX sur le cluster Vagrant
2. Valider les fonctionnalités requises (regex, rate limiting, WAF)
3. Migrer progressivement les routes Ingress vers HTTPRoute
4. Valider le WAF avec des tests d'intrusion basiques

---

## Ressources

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [APISIX Ingress Controller](https://apisix.apache.org/docs/ingress-controller/getting-started/)
- [Coraza WAF](https://coraza.io/)
- [OWASP Core Rule Set](https://coreruleset.org/)
- [Migration Guide Ingress NGINX](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/)

---

*Document généré : Février 2026*
