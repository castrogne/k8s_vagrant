# Problèmes Snapshot Restore avec Kubernetes + Calico

## Introduction

**Calico est indispensable** pour faire fonctionner Kubernetes. Sans réseau CNI (comme Calico), les pods ne peuvent pas communiquer et les nodes restent en état "NotReady".

---

## Solutions envisagées

1. **suspend/resume** - Solution rapide
2. **halt/snapshot restore** - Snapshot VirtualBox (NE FONCTIONNE PAS)
3. **destroy + up complet** - Solution complète
4. **backup/restore** - Voir [INSTALL.md](../INSTALL.md#backup-et-restauration)

---

## Résultats des tests

| Solution | Résultat |
|----------|----------|
| suspend/resume | ✅ OK |
| halt/snapshot restore | ❌ KO |
| destroy + up complet | ✅ OK |

---

## Troubleshooting

### Problème 1: halt/snapshot restore ne fonctionne pas

Après un halt/snapshot restore:
- Les pods Calico sont "Running" mais pas "Ready"
- Erreur: `BGP not established`
- Erreur: `connection is unauthorized`
- Le réseau ne fonctionne pas

**Cause:** L'état de Calico dans etcd devient incohérent avec l'état réel des VMs après le restore.

---

### Problème 2: worker2 est NotReady après suspend/resume
Ce problème est aléatoire, mais la solution 2 ci-dessous permet de récupérer un kube stable.

#### Solution 1: kubeadm join
- ❌ Ne permet pas de résoudre le problème
- Erreur: `e1000 eth1: Detected Tx Unit Hang`

#### Solution 2: destroy + up worker2
- ✅ Solution qui fonctionne!
- Commandes:
  ```
  vagrant destroy worker2
  vagrant up worker2 --provision
  ```

### Tester le réseau:

#### Créer un pod de test
```
kubectl run test-pod --image=nginx --restart=Never
```

#### Forcer sur un node spécifique
```
kubectl run test-pod --image=nginx --restart=Never --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker2"}}}'
```

#### Tester la connectivité
```
kubectl exec test-pod -- curl -I https://8.8.8.8
```

---

## Tests Backup/Restore (22 mars 2026)

### Méthode 1: tar de /var/lib/etcd

**Résultat : ÉCHEC**

Le backup etcd avec `tar` produit un fichier quasi vide :
```
var/lib/etcd/
var/lib/etcd/member/wal/
var/lib/etcd/member/snap/db
```

Aucune donnée applicative (pods, services, ConfigMaps, etc.) n'est présente.

**Cause :**
- etcd utilise un mécanisme de write-ahead log (WAL) et de snapshots
- Arrêter kubelet/containerd ne crée pas un snapshot cohérent d'etcd
- tar capture les fichiers physiques mais pas l'état transactionnel de la base etcd

---

### Méthode 2: etcdctl snapshot save

**Résultat : PARTIEL**

Le snapshot avec `etcdctl snapshot save` capture un état cohérent (4.4 MB compressé ~500KB).

**Problème identifié :**
- Le snapshot contient TOUTES les configurations du cluster (IP, certificats, etc.)
- Après restore, l'IP advertise du kube-apiserver est restaurée (ex: 192.168.56.11)
- Mais l'IP actuelle du cluster peut être différente (ex: 10.0.10.11)
- → Incompatibilité qui bloque le cluster

**Symptômes après restore raté :**
```
kubelet: "No need to create a mirror pod, since failed to get node info from the cluster"
kubelet: "Unable to register node with API server" - Timeout
```

---

## Solutions alternatives

### Solution 1: Corriger l'IP après restore (complexe, risqué)

```bash
# Récupérer l'IP actuelle du node
IP=$(vagrant ssh control-plane1 -c "hostname -I | awk '{print \$1}'")

# Corriger l'IP dans le manifest kube-apiserver
vagrant ssh control-plane1 -c "sudo sed -i 's/192.168.56.11/\${IP}/g' /etc/kubernetes/manifests/kube-apiserver.yaml"

# Redémarrer kubelet
vagrant ssh control-plane1 -c "sudo systemctl restart kubelet"
```

**Risque** : Haut - peut créer d'autres incohérences

---

### Solution 2: Sauvegarder les ressources applicatives (recommandée)

```bash
# Exporter les ressources applicatives (exclure namespaces système)
kubectl get all -A -o yaml | \
  grep -v 'namespace: kube-system' | \
  grep -v 'namespace: calico' | \
  grep -v 'namespace: kube-ingress' | \
  grep -v 'namespace: kube-monitoring' \
  > backups/resources.yaml

# Après fresh install, réappliquer
kubectl apply -f backups/resources.yaml
```

**Avantage** : Simple, prévisible, fonctionne toujours

---

## Tableau comparatif des méthodes

| Méthode | Restore sur même cluster | Restore après destroy | Complexité |
|---------|-------------------------|---------------------|------------|
| tar /var/lib/etcd | ❌ | ❌ | Faible |
| etcdctl snapshot | ⚠️ Partiel (IP mismatch) | ❌ | Moyenne |
| kubectl get all -o yaml | ✅ | ✅ | Faible |

---

## Conclusions

1. **La méthode tar ne fonctionne pas** pour sauvegarder etcd
2. **Le restore etcdctl snapshot échoue** car il restaure aussi les configurations réseau
3. **La méthode kubectl export** est la plus simple et fiable pour un homelab
4. **suspend/resume** reste la solution recommandée pour un usage quotidien

---

## Recommandation pour homelab

| Besoin | Solution |
|--------|----------|
| Usage quotidien | `vagrant suspend/resume` |
| Backup applicatif fiable | `kubectl get all -o yaml` |
| Snapshot complet | Solution professionnelle (Velero) |

Pour un backup/restore fiable et simple, utiliser la méthode `kubectl get all -o yaml` documentée dans [INSTALL.md](../INSTALL.md#backup-et-restauration).

---

## Ouverture

Les limitations observées avec etcdctl snapshot (IP mismatch, configurations système) pourraient être résolues par des outils professionnels de backup Kubernetes comme **Velero**, qui gère automatiquement ces incohérences et offre des fonctionnalités avancées (backup sélectif, volumes persistants, etc.).

Voir [ANALYSE_VELERO.md](./ANALYSE_VELERO.md) pour les tests planifiés.

---

## Références

- [etcd backup and restore - Kubernetes docs](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [Article Stéphane Robert - Backup Kubernetes](https://blog.stephane-robert.info/docs/conteneurs/orchestrateurs/kubernetes/backup-restore/)
