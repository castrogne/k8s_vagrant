# Mise en place d'un cluster Kubernetes en local avec Vagrant

## Introduction

Ce projet permet de déployer un cluster Kubernetes complet en local avec Vagrant et VirtualBox. Il utilise Calico comme CNI et est configuré pour le développement local.

## Stack

| Composant | Version |
|-----------|---------|
| Vagrant | 2.3.x |
| VirtualBox | 7.x |
| Ubuntu | 24.04 LTS |
| Kubernetes | 1.35.x |
| Container Runtime | containerd |
| CNI | Calico v3.25 |

## Prérequis

- Vagrant installé
- VirtualBox installé
- kubectl installé (voir [Installation kubectl](#installation-kubectl))

## Installation kubectl

**Méthode recommandée (installation manuelle)** :
```bash
curl -LO "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

**Via snap (version peut être obsolète)** :
```bash
snap install kubectl --classic
```

Vérifier :
```bash
kubectl version --client
```

## Déploiement rapide

```bash
# Déployer le cluster
vagrant up --provision

# Récupérer le kubeconfig
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig.yaml

# Configurer l'accès permanent (ajouter au .bashrc)
export KUBECONFIG=$PWD/kubeconfig.yaml

# Installer Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml

# Vérifier le cluster
kubectl get nodes -o wide
```

⏳ Attendre 5-10 minutes pour le provisionnement complet.

## Usage quotidien

```bash
# Arrêter le cluster
vagrant suspend

# Reprendre
vagrant resume
```

⚠️ **Important** : Les snapshots VirtualBox ne fonctionnent pas de manière fiable avec Calico. Utilisez `vagrant suspend/resume`.
⚠️ **Important** : L'utilisation de suspend/resume est également assez aléatoire. le 'up" a été accéléré via pré-download automatique, et velero est conseillé.

## Documentation détaillée

Pour les procédures complètes (installation, services, troubleshooting, backup) :

- [Installation et utilisation](./docs/INSTALL.md)
- [Analyse snapshot/restore](./docs/ANALYSE_SNAPSHOT_RESTORE.md)

## Workshops

- [Backups Velero](./workshops/velero/ANALYSE_VELERO.md)
- [Prometheus & GRafana](./workshops/preometheus/PROMETHEUS_UPGRADE.md)
- [Gateway Prometheus](./workshops/Gateway/GATEWAY_API_MIGRATION.md)
  - [Gateway APISIX](./workshops/Gateway/Workshop_APISIX.md)

## Dépannage

### VirtualBox kernel module non chargé

```bash
sudo /sbin/vboxconfig
# ou
sudo modprobe vboxdrv
```

### Node NotReady après resume

```bash
vagrant destroy worker2
vagrant up worker2 --provision
```

### Tester le réseau

```bash
kubectl run test-pod --image=nginx --restart=Never
kubectl exec test-pod -- curl -I https://8.8.8.8
```

## Configuration

- Version Kubernetes : modifier `KUBE_VERSION` dans `scripts/vagrant/init_k8s.sh`
- Nombre de nodes : modifier `NMB_CONTROL_PLANE` et `NMB_WORKER` dans `Vagrantfile`

## Références

- [Documentation originale](https://kanops.io/blog/deployer-cluster-kubernetes-local-vagrant)
- [Kubernetes docs](https://kubernetes.io/docs/)
- [Calico docs](https://docs.tigera.io/calico/latest/)
