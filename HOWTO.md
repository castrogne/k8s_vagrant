# Guide d'installation et d'utilisation du cluster Kubernetes

## Prérequis

### 0- Installation de kubectl et autocompletion
Voir : https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

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

### 3- Installation du réseau (Calico)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
```

### 4- Vérification du cluster
```bash
kubectl get nodes -o wide
```

### 5- Création d'un snapshot (recommandé)
```bash
vagrant snapshot save cluster-ready
```

## Workflow avec Snapshots (Recommandé pour usage personnel)

### Arrêt du cluster
```bash
vagrant halt
```

### Redémarrage rapide (instantané)
```bash
vagrant snapshot restore cluster-ready
```

### Avantages des snapshots
- **Restauration instantanée** : quelques secondes seulement
- **État complet préservé** : mémoire, disque, services, certificats
- **Pas de réinitialisation** : évite les problèmes de certificats expirés
- **Multiple snapshots** : possibilité d'avoir plusieurs états sauvegardés

### Commandes utiles pour les snapshots
```bash
# Lister tous les snapshots
vagrant snapshot list

# Créer un nouveau snapshot
vagrant snapshot save nom-du-snapshot

# Restaurer un snapshot spécifique
vagrant snapshot restore nom-du-snapshot

# Supprimer un snapshot
vagrant snapshot delete nom-du-snapshot
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

## Références

- Documentation originale : https://kanops.io/blog/deployer-cluster-kubernetes-local-vagrant
- Repository GitHub : https://github.com/kanops/k8s_vagrant
- Configuration multi-clusters : https://kubernetes.io/fr/docs/tasks/access-application-cluster/configure-access-multiple-clusters/