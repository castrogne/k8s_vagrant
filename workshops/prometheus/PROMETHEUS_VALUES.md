# Guide kube-prometheus-stack - Variables du fichier local

## Configuration du chart

### Installation
- `crds.enabled: true` - Installe les Custom Resource Definitions de l'opérateur

### prometheus
- `enabled: true` - Active le déploiement de Prometheus

### prometheus.prometheusSpec

**Rétention**
- `retention: 2h` - Durée de conservation des métriques
- `retentionSize: 500MiB` - Taille maximale des données. Optionnel, n'a pas de valeur par défaut. Les deux conditions (temps ET taille) doivent être réunies pour supprimer les données. Sert de garde-fou pour éviter de remplir le disque.

**Cross-namespace monitoring**
- `ruleSelectorNilUsesHelmValues: false` - Autorise les PrometheusRule de tous les namespaces
- `serviceMonitorNilUsesHelmValues: false` - Autorise les ServiceMonitor de tous les namespaces
- `podMonitorNilUsesHelmValues: false` - Autorise les PodMonitor de tous les namespaces

**Distribution des pods**
- `topologySpreadConstraints` - Répartition des pods sur les nœuds
  - `maxSkew: 1` - Débalancement max autorisé entre nœuds
  - `topologyKey: kubernetes.io/hostname` - Clé de label pour le partitionnement
  - `whenUnsatisfiable: DoNotSchedule` - Refuse le pod si impossible à équilibrer
  - `labelSelector` - Sélectionne les pods à répartir
    - `prometheus: prometheus-kube-prometheus-prometheus` - Label automatiquement ajouté par le chart aux pods Prometheus

**Nombre de replicas**
- `replicas: 1` - Nombre de pods Prometheus

### nodeExporter
- `enabled: true` - Active le node-exporter (métriques système des nœuds)
- `priorityClassName: system-node-critical` - Priorité Kubernetes du pod

### alertmanager
- `enabled: false` - Désactive Alertmanager

### grafana
- `enabled: true` - Active Grafana
- `persistence.enabled: false` - Désactive la persistance
- `replicas: 1` - Nombre de pods
- `useStatefulSet: true` - Utilise un StatefulSet
- `sidecar.dashboards` - Import auto des dashboards via ConfigMaps
- `datasources` - Configuration de la datasource Prometheus

### defaultRules
- `create: false` - Désactive les règles d'alertes par défaut

---

## Pour aller plus loin

### PriorityClass (priorité des pods)

Les PriorityClasses déterminent l'ordre de priorité des pods lors du scheduling. Kubernetes intègre deux PriorityClasses par défaut :

```bash
kubectl get priorityclass
```

| Nom | Valeur | Usage |
|-----|--------|-------|
| `system-node-critical` | 2000001000 | Plus haute priorité - composants système critiques |
| `system-cluster-critical` | 2000000000 | Addons critiques (Coredns, metrics-server, etc.) |

**Pourquoi utiliser `system-node-critical` ?**
Cette priorité assure que le node-exporter ne sera jamais évincé par d'autres pods en cas de ressources limitées sur le nœud. C'est important car les métriques de monitoring doivent toujours être disponibles.

---

### Mécanisme d'import automatique des dashboards Grafana

Grafana peut importer automatiquement des dashboards via des ConfigMaps. Voici comment ça fonctionne :

**1. Le ConfigMap**
Un fichier YAML contient le dashboard JSON et un label spécial :

```yaml
kind: ConfigMap
metadata:
  labels:
    grafana_dashboard: "1"  # Ce label déclenche l'import
  name: grafana-home-dashboard
  namespace: kube-monitoring
data:
  home.json: |
    { ... contenu du dashboard ... }
```

**2. Le sidecar Grafana**
Le chart déploie un conteneur sidecar alongside Grafana. Ce sidecar a pour rôle de surveiller le namespace à la recherche de ConfigMaps avec le label `grafana_dashboard: "1"`.

**3. L'import automatique**
Quand le sidecar détecte un nouveau ConfigMap :
- Il lit le fichier JSON (ici `home.json`)
- Il le copie dans le répertoire `/var/lib/grafana/dashboards/` du conteneur Grafana
- Le dashboard devient immédiatement disponible dans l'interface Grafana sans redémarrage

**4. Résultat**
Le fichier `home.json` apparaît comme dashboard d'accueil dans Grafana, sans aucune manipulation manuelle.

**Pour résumé :**
```
ConfigMap (label: grafana_dashboard: "1")
    ↓
Sidecar Grafana scrute le namespace
    ↓
Copie le JSON dans /var/lib/grafana/dashboards/
    ↓
Dashboard disponible dans l'interface
```
