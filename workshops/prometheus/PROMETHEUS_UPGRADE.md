# Guide de mise à jour kube-prometheus-stack

## Contexte
- Version initiale: 55.5.1
- Version cible: 82.2.0
- Écart: 27 versions majeures

## Méthode simple (recommandée pour environnement de dev)

### Étapes
1. Supprimer le release helm
2. Supprimer le namespace (pour tout nettoyer)
3. Recréer le namespace
4. Réinstaller avec la nouvelle version

### Commandes
```bash
# Supprimer le release
helm -n kube-monitoring uninstall prometheus

# Supprimer le namespace (nettoie tout)
kubectl delete namespace kube-monitoring --grace-period=0 --force

# Recréer le namespace
kubectl create namespace kube-monitoring

# Réinstaller
helm -n kube-monitoring upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -f scripts/helm/kube-monitoring/kube-prometheus-stack.yml \
  --version 82.2.0
```

---

## Ce qu'il NE FAUT PAS faire

### 1. Supprimer les CRDs puis faire `helm install`
- Les CRDs ne sont pas recréées automatiquement lors d'un `helm install`
- Erreur: `field not declared in schema`

### 2. Supprimer les CRDs puis faire `helm uninstall`
- Arrive à un état instable où le release reste "uninstalling" indéfiniment
- helm essaie de nettoyer des ressources qui n'existent plus

---

## Alternative propre (pour environnement de prod)

Pour préserver les données et configurations existantes:
1. Mettre à jour les CRDs sans les supprimer
2. Utiliser `helm template --include-crds | kubectl apply`

```bash
# Télécharger le chart
helm pull prometheus-community/kube-prometheus-stack --version 82.2.0 --untar

# Appliquer les CRDs
kubectl apply -f kube-prometheus-stack/crds/

# Faire l'upgrade
helm upgrade --install prometheus prometheus-community/kube-prometheus -n kube-monitoring-stack \
  -f scripts/helm/kube-monitoring/kube-prometheus-stack.yml \
  --version 82.2.0
```

---

## Notes
- Cette méthode a été testée avec succès de 55.5.1 → 82.2.0
- La configuration locale (values) est simple et ne contient pas de breaking changes majeurs
