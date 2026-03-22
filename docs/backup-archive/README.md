# Archive : Scripts Backup/Restore etcdctl

## Description

Ces scripts sont des tentatives de backup/restore de cluster Kubernetes utilisant `etcdctl snapshot save`.

## Statut : ❌ ARCHIVÉ - NE FONCTIONNE PAS

Ces scripts **ne fonctionnent pas** de manière fiable pour un restore complet.

## Problèmes identifiés

### Problème 1: IP mismatch après restore

- Le snapshot etcd contient l'IP advertise du kube-apiserver (ex: `192.168.56.11`)
- Après restore, l'IP actuelle du cluster peut être différente (ex: `10.0.10.11`)
- → Le cluster ne peut plus communiquer

**Symptômes :**
```
kubelet: "No need to create a mirror pod, since failed to get node info from the cluster"
kubelet: "Unable to register node with API server" - Timeout
```

### Problème 2: Restauration après destroy impossible

- Après `vagrant destroy && vagrant up`, les certificats PKI sont régénérés
- Le snapshot contient les anciens certificats
- → Mismatch de certificats

## Solutions alternatives

Pour un backup/restore fiable, utiliser :

1. **`kubectl get all -o yaml`** - Méthode simple et fonctionnelle
   - Documentation : [INSTALL.md](../../INSTALL.md#backup-et-restauration)

2. **Velero** - Solution professionnelle
   - Tests planifiés : [ANALYSE_VELERO.md](../ANALYSE_VELERO.md)

## Analyse complète

Voir : [ANALYSE_SNAPSHOT_RESTORE.md](../ANALYSE_SNAPSHOT_RESTORE.md)

## Contenu

```
backup-archive/
├── README.md           # Ce fichier
├── backup-k8s.sh      # Script de backup (archivé)
└── restore-k8s.sh    # Script de restore (archivé)
```
