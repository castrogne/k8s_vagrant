# Problèmes Snapshot Restore avec Kubernetes + Calico

## Introduction

**Calico est indispensable** pour faire fonctionner Kubernetes. Sans réseau CNI (comme Calico), les pods ne peuvent pas communiquer et les nodes restent en état "NotReady".

---

## Solutions envisagées

1. **suspend/resume** - Solution rapide
2. **halt/snapshot restore** - Snapshot VirtualBox
3. **destroy + up complet** - Solution complète
4. **backup/restore etcd** - TODO

---

## Résultats des tests

| Solution | Résultat |
|----------|----------|
| suspend/resume | ✅ OK |
| halt/snapshot restore | ❌ KO |
| destroy + up complet | ✅ OK |
| backup/restore etcd | ⏳ TODO |

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
