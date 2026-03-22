# Analyse Velero - Solution professionnelle de backup Kubernetes

## Objectif

Tester Velero pour le backup et restore de clusters Kubernetes, afin de pallier les limitations des méthodes actuelles (etcdctl snapshot, kubectl export).

Velero est un outil recommandé par la CNCF pour la sauvegarde et restauration de clusters Kubernetes.

## Installation

### Prérequis
- Cluster Kubernetes fonctionnel
- Stockage compatible S3 (MinIO, AWS S3, Azure Blob, etc.)

### Installation planifiée
[À documenter lors de la session de test]

## Tests planifiés

### Test 1: Installation de Velero
- [ ] Installation de Velero CLI
- [ ] Installation du serveur Velero sur le cluster
- [ ] Configuration du stockage (MinIO ou autre)

### Test 2: Backup sur cluster actif
- [ ] Créer un pod de test
- [ ] Exécuter un backup complet
- [ ] Vérifier que le backup est stocké

### Test 3: Restore sur même cluster
- [ ] Supprimer le pod de test
- [ ] Restaurer le backup
- [ ] Vérifier que le pod est revenu

### Test 4: Restore après destroy+up
- [ ] Détruire le cluster
- [ ] Recréer le cluster
- [ ] Restaurer le backup
- [ ] Vérifier que tout est revenu

## Workflow attendu

```bash
# Installation
velero install --provider aws --bucket backups --secret-file ./credentials-velero --backup-location-config region=minio,s3ForcePathStyle="true",publicUrl=http://minio:9000 --snapshot-location-config region=minio

# Backup
velero backup create mon-backup --include-namespaces mon-app

# Restore
velero restore create --from-backup mon-backup
```

## Critères de succès

- [ ] Le backup capture toutes les ressources applicatives
- [ ] Le restore sur même cluster fonctionne
- [ ] Le restore après destroy+up fonctionne
- [ ] Les volumes persistants sont sauvegardés (si applicable)
- [ ] La solution est plus simple/fiable que etcdctl snapshot

## Conclusions

[À remplir après les tests]
