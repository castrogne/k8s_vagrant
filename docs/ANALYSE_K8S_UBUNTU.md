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

## 6. Problèmes rencontrés et corrections

### 6.1 CrashLoopBackOff kube-controller-manager et kube-proxy

#### Problème identifié
Erreurs observées avec K8s 1.35 sur Ubuntu 22.04 :
```
kube-controller-manager: CrashLoopBackOff
kube-proxy: CrashLoopBackOff
coredns: Pending
calico-node: 0/0 Ready
```

Messages d'avertissement :
```
WARNING ContainerRuntimeVersion]: You must update your container runtime to a version that supports the CRI method RuntimeConfig
detected that the sandbox image "registry.k8s.io/pause:3.8" is inconsistent with that used by kubeadm
```

Ces erreurs indiquent une incompatibilité entre containerd 1.7.28 (Ubuntu 22.04) et les exigences CRI de Kubernetes 1.35.

#### Solution : Installation manuelle de Containerd 2.x

Même avec Ubuntu 24.04, containerd intégré est encore en version 1.7.x, insuffisant pour K8s 1.35 qui exige CRI v1 complet.

##### Composants installés manuellement :
| Composant | Version | Source |
|-----------|---------|---------|
| containerd | 2.0.2 | GitHub releases |
| runc | 1.2.0 | GitHub releases |
| CNI plugins | 1.4.0 | GitHub releases |

##### Étapes d'installation :
1. Désactiver swap
2. Installer les dépendances (apt-transport-https, curl, wget, gnupg)
3. Télécharger containerd 2.0.2 depuis GitHub
4. Extraire vers /usr/local
5. Télécharger et installer runc vers /usr/local/sbin
6. Télécharger et installer CNI plugins vers /opt/cni/bin
7. Configurer containerd avec SystemdCgroup=true
8. Créer le service systemd pour containerd

##### Commandes clés :
```bash
# Containerd
wget https://github.com/containerd/containerd/releases/download/v2.0.2/containerd-2.0.2-linux-amd64.tar.gz
tar -C /usr/local -xzf containerd-2.0.2-linux-amd64.tar.gz

# Runc
wget https://github.com/opencontainers/runc/releases/download/v1.2.0/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# CNI plugins
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.4.0.tgz
```

##### Résumé des modifications :
- `Vagrantfile` - Ubuntu 24.04 + ressources augmentées
- `scripts/vagrant/init_k8s.sh` - Installation manuelle de containerd 2.x, runc 1.2.0, CNI plugins 1.4.0

---

### 6.2 IP interne identique sur les nodes Vagrant

#### Symptôme
Tous les nodes affichent la **même IP interne** (`10.0.2.15`) via `kubectl get nodes -o wide`:
```
NAME             INTERNAL-IP
control-plane1   10.0.2.15
worker1          10.0.2.15
worker2          10.0.2.15
```

Cette IP est l'IP NAT de VirtualBox (10.0.2.15), pas l'IP du réseau host-only (192.168.56.x) défini dans le Vagrantfile.

#### Cause
Kubelet utilise par défaut la première interface réseau disponible, qui est l'interface NAT (10.0.2.15) au lieu de l'interface host-only (192.168.56.x).

#### Problème supplémentaire découvert
Après avoir configuré kubelet avec `--node-ip=192.168.56.x`, un nouveau problème est apparu:
- Les nodes ont maintenant des IPs uniques (192.168.56.11, 192.168.56.21, etc.)
- Mais la communication inter-VMs échoue: `no route to host`
-的原因是 VirtualBox **Host-Only** ne permet pas la communication inter-VMs par défaut!

#### Solution finale : Réseau Internal Network VirtualBox

Au lieu d'utiliser le réseau Host-Only pour la communication inter-VMs, on utilise un **réseau Internal Network** VirtualBox.

##### Configuration Vagrantfile
```ruby
# Host-only network (pour host ↔ VM)
config.vm.network "private_network", ip: "192.168.56.x"

# Internal network (pour VM ↔ VM)
config.vm.network "private_network", 
  virtualbox__intnet: "k8s-internal",
  ip: "10.0.10.x"
```

##### Schéma réseau final
```
Host ←→ Host-Only eth1 (192.168.56.x) ←→ VM
         ↑
    kubectl fonctionne

Internal Network eth2 (10.0.10.x) ←→ VM
         ↑
    VM↔VM communication
```

##### Script kubelet mis à jour (init_k8s.sh)
```bash
# Détecte d'abord le réseau internal (10.0.10.x)
PRIVATE_IP=$(ip -4 addr show | grep "10.0.10" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# Fallback vers host-only (192.168.56.x)
if [ -z "$PRIVATE_IP" ]; then
    PRIVATE_IP=$(ip -4 addr show | grep "192.168.56" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi
```

##### IPs attendues après fix:
| Node | IP Internal Network |
|------|-------------------|
| control-plane1 | 10.0.10.11 |
| worker1 | 10.0.10.21 |
| worker2 | 10.0.10.22 |

##### Bonus: Génération automatique des MAC addresses
Pour éviter les conflits d'adresses MAC (VMs avec la même MAC), ajout dans Vagrantfile:
```ruby
v.customize ["modifyvm", :id, "--macaddress1", "auto"]
```

---

*Analyse réalisée le 26 janvier 2025, mise à jour le 22 février 2025*