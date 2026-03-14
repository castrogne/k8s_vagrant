# Guide d'installation et d'utilisation du cluster Kubernetes

## Prérequis

### 0- Installation de kubectl et autocompletion
Voir : https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

**Important** : kubectl doit être compatible avec la version du cluster. Si le cluster utilise Kubernetes 1.35+, kubectl doit être en version 1.35 ou ultérieure.

**Via snap (version peut être obsolète)** :
```bash
snap install kubectl --classic
snap refresh kubectl
```

**Méthode recommandée (installation manuelle)** :
```bash
# Télécharger la dernière version
curl -LO "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"

# Rendre executable et déplacer
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

**Vérifier** :
```bash
kubectl version --client
```

### 1- Installation de VirtualBox
Utilisez le script `install_virtualbox.sh` (testé sur Ubuntu 22.04)

### 2- Installation de Krew (gestionnaire de plugins kubectl)
```bash
./install_krew.sh
```

## Installation initiale du cluster

### 1- Déploiement avec Vagrant
```bash
vagrant up --provision
```

### 2- Configuration du kubeconfig
```bash
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig.yaml

# Configuration permanente (ajouter au .bashrc)
export KUBECONFIG=$HOME/Projets/perso/k8s_vagrant/kubeconfig.yaml

# Ou temporaire pour la session
export KUBECONFIG=$PWD/kubeconfig.yaml
```

### 3- Installation du réseau (Calico)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
```

### 4- Vérification du cluster
```bash
kubectl get nodes -o wide
```

**Note importante** : L'installation utilise maintenant la méthode manuelle pour contourner les problèmes de dépôts pkgs.k8s.io. Les packages sont téléchargés directement depuis les releases officielles Kubernetes.

## Workflow avec suspend/resume

> ⚠️ **Attention:** Les snapshots VirtualBox ne fonctionnent pas de manière fiable avec Calico. Voir: [docs/ANALYSE_SNAPSHOT_RESTORE.md](./docs/ANALYSE_SNAPSHOT_RESTORE.md)

### Arrêt du cluster
```bash
vagrant suspend
```

### Redémarrage rapide
```bash
vagrant resume
```

### Résolution de problèmes
Si après un resume un node est NotReady, voir: [docs/ANALYSE_SNAPSHOT_RESTORE.md#troubleshooting](./docs/ANALYSE_SNAPSHOT_RESTORE.md#troubleshooting)

### Commandes utiles
```bash
# État des VMs
vagrant status
```

## Installation rapide des services additionnels

Depuis le répertoire `scripts` :

```bash
# Ajout des repositories Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# Création des namespaces
kubectl create ns kube-monitoring
kubectl create ns kube-ingress

# Installation ingress-nginx
helm -n kube-ingress upgrade --install kube-ingress ingress-nginx/ingress-nginx -f helm/kube-ingress/ingress-nginx.yml --version 4.7.1

# Installation cert-manager
kubectl apply -n kube-ingress -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml
helm -n kube-ingress upgrade --install cert-manager jetstack/cert-manager -f helm/kube-ingress/cert-manager.yml --version 1.13.1

# Installation metrics-server
helm upgrade --install --set 'args={--kubelet-insecure-tls}' --namespace kube-system metrics-server metrics-server/metrics-server

# Installation prometheus/grafana
helm -n kube-monitoring upgrade --install prometheus prometheus-community/kube-prometheus-stack -f helm/kube-monitoring/kube-prometheus-stack.yml --version 55.5.1
```

## Dépannage

### VirtualBox kernel module non chargé
Si vous rencontrez cette erreur lors de `vagrant up` :
```
VirtualBox is complaining that the kernel module is not loaded. Please
run `VBoxManage --version` or open the VirtualBox GUI to see the error
message which should contain instructions on how to fix this error.
```

Exécutez l'une de ces commandes pour corriger le problème :
```bash
sudo /sbin/vboxconfig
```
Ou :
```bash
sudo modprobe vboxdrv
```

### Erreur "pod does not exist"
Voir : 
- https://medium.com/@mukesh.yadav_86837/how-to-fix-error-unable-to-upgrade-connection-pod-does-not-exist-fa90b7d1e44b
- https://medium.com/@kanrangsan/how-to-specify-internal-ip-for-kubernetes-worker-node-24790b2884fd

### Tester le réseau après un problème

#### Créer un pod de test
```bash
kubectl run test-pod --image=nginx --restart=Never
```

#### Forcer un pod sur un node spécifique
```bash
kubectl run test-pod --image=nginx --restart=Never --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker2"}}}'
```

#### Tester la connectivité internet
```bash
kubectl exec test-pod -- curl -I https://8.8.8.8
```

## Backup et Restauration

### À propos
Ces scripts sont à utiliser **uniquement** lors d'une montée de version de Kubernetes nécessitant un `vagrant destroy && vagrant up`. Pour un usage quotidien, utiliser `vagrant suspend` et `vagrant resume`.

### Prérequis
- Cluster Kubernetes fonctionnel
- Vagrant installé

### Backup (avant upgrade)

```bash
# Créer un backup du cluster
./scripts/vagrant/backup-k8s.sh
```

Un dossier `backups/k8s-AAAAMMJJ_HHMMSS/` sera créé contenant :
- `etcd.tar.gz` - Base de données complète du cluster
- `pki.tar.gz` - Certificats Kubernetes

### Restauration (après upgrade)

```bash
# Lister les backups disponibles
ls ./backups/

# Restaurer un backup spécifique
./scripts/vagrant/restore-k8s.sh 20260221_143000
```

### Notes importantes

- **suspend/resume = solution recommandée** pour un usage quotidien
- **Backup/Restore = uniquement pour les upgrades majeurs**
- Le backup contient tout l'état (Helm, déploiements, services, etc.)
- Pas besoin de vos fichiers values.yaml - tout est dans etcd

### Pour un usage quotidien

```bash
# Arrêter le cluster
vagrant suspend

# Reprendre plus tard
vagrant resume
```

## Références

- Documentation originale : https://kanops.io/blog/deployer-cluster-kubernetes-local-vagrant
- Repository GitHub : https://github.com/kanops/k8s_vagrant
- Configuration multi-clusters : https://kubernetes.io/fr/docs/tasks/access-application-cluster/configure-access-multiple-clusters/