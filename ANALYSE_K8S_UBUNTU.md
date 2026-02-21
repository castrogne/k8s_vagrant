# Analyse - Choix de l'OS pour Kubernetes 1.35

## Contexte
Après plusieurs tentatives infructueuses de faire fonctionner Kubernetes 1.35 sur Ubuntu 22.04 (problèmes de CrashLoopBackOff sur kube-controller-manager et kube-proxy), une analyse approfondie a été menée pour trouver la meilleure solution.

---

## 1. Option: Downgrade Kubernetes vers 1.31 + ressources

### Raisons de cette possibilité :
- K8s 1.31 est une version **stable et éprouvée** (support jusqu'à février 2027)
- Containerd 1.7.28 sur Ubuntu 22.04 est **compatible** avec 1.31
- Plus de documentation/discussions sur les problèmes connus
- En augmentant les ressources (control-plane: 3-4GB, worker: 4-6GB)

### Pourquoi cette option n'a pas été retenue :
- K8s 1.35 est plus moderne et avec plus de fonctionnalités
- Le problème de fond était containerd trop ancien, pas les ressources
- L'objectif était de garder une version récente de Kubernetes

---

## 2. Option: Ubuntu 24.04

### Raisons du choix :
- **Containerd plus récent** via les dépôts Canonical (parce qu'Ubuntu ajoute ses propres packages plus récents que Debian)
- Ubuntu 24.04 = **Debian 12 (Bookworm)** + packages Ubuntu plus récents
- Containerd natif plus compatible avec K8s 1.35 et ses exigences CRI v1
- box `bento/ubuntu-24.04` disponible et fonctionnelle

### Précision technique :
Ubuntu s'appuie sur Debian mais maintient ses propres dépôts. Ubuntu 24.04 dérive de Debian 12 (Bookworm), mais les paquets des dépôts Ubuntu sont **plus récents** que ceux de Debian Stable. C'est pourquoi containerd est plus récent sur Ubuntu 24.04 que sur Debian 12 natif.

---

## 3. Option: Autres distributions

### Solutions envisagées et écartées :

| Distribution | Pourquoi écartée |
|-------------|------------------|
| **Debian 12** | Packages **plus anciens** que Ubuntu (problème inverse!) - Debian Stable fige ses paquets au moment de la release |
| **Rocky Linux 9** | Non adaptée, nouvelles commandes à apprendre (dnf/yum) |
| **Fedora** | Non adaptée, gestion RPM différente |
| **AlmaLinux** | Non supportée officiellement par Kubernetes |
| **Alpine** | Non supportée par Kubernetes |
| **Flatcar** | Trop spécifique, orientée conteneurs uniquement |

---

## 4. Solution finale retenue : Ubuntu Server 24.04

### Choix final :
```ruby
IMAGE = "bento/ubuntu-24.04"  # Ubuntu Server sans GUI
```

### Avantages :
- **Ubuntu Server** (pas Desktop) = sans GUI = léger et minimal
- Containerd natif récent pour K8s 1.35
- Même gestion `apt` qu'Ubuntu 22.04 - pas de changement de syntaxe
- box disponible (bento/ubuntu-24.04)
- Support jusqu'en 2029 (LTS)

### Ressources machine disponibles :
- RAM totale: 15 GB
- CPUs: 8 (Intel i7-6700HQ)
- Plus de 1.9 To de disque disponible

---

## 5. Configuration machines virtuelles

| VM | RAM suggérée | CPUs |
|----|-------------|------|
| Control-plane | 3-4 GB | 2-4 |
| Worker | 4-6 GB | 2-4 |

---

## 6. Problèmes rencontrés (historique)

### Erreurs observées avec K8s 1.35 sur Ubuntu 22.04 :
```
kube-controller-manager: CrashLoopBackOff
kube-proxy: CrashLoopBackOff
coredns: Pending
calico-node: 0/0 Ready
```

### Messages d'avertissement :
```
WARNING ContainerRuntimeVersion]: You must update your container runtime to a version that supports the CRI method RuntimeConfig
detected that the sandbox image "registry.k8s.io/pause:3.8" is inconsistent with that used by kubeadm
```

Ces erreurs indiquent une incompatibilité entre containerd 1.7.28 (Ubuntu 22.04) et les exigences CRI de Kubernetes 1.35.

---

## 7. Résumé des modifications à apporter

1. Changer `IMAGE` dans Vagrantfile vers `bento/ubuntu-24.04`
2.eventuellement augmenter les ressources si nécessaire
3. Recréer le cluster avec `vagrant destroy && vagrant up --provision`

---

*Analyse réalisée le 26 janvier 2025*