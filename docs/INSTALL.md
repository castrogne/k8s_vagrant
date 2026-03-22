# Guide d'installation et d'utilisation détaillée

Ce document contient la procédure complète d'installation et d'utilisation du cluster Kubernetes.

## Table des matières

1. [Prérequis](#prérequis)
2. [Installation initiale](#installation-initiale-du-cluster)
3. [Workflow suspend/resume](#workflow-avec-suspendresume)
4. [Installation des services](#installation-rapide-des-services-additionnels)
5. [Dépannage](#dépannage)
6. [Backup et Restauration](#backup-et-restauration)
7. [Références](#références)

---

## Prérequis

### 0- Installation de kubectl et autocompletion

Voir : https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

**Important** : kubectl doit être compatible avec la version du cluster (1.35+).

**Via snap (version peut être obsolète)** :
```bash
snap install kubectl --classic
snap refresh kubectl
```

**Méthode recommandée (installation manuelle)** :
```bash
curl -LO "https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl"
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
./scripts/install_krew.sh
```

---

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

---

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

---

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

---

## Dépannage

### VirtualBox kernel module non chargé
Si vous rencontrez cette erreur lors de `vagrant up` :
```
VirtualBox is complaining that the kernel module is not loaded. Please
run `VBoxManage --version` or open the VirtualBox GUI to see the error
message which should finish with instructions on how to fix this error.
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

---

## Backup et Restauration

### Méthode : kubectl export (simple et fiable)

Cette méthode exporte les ressources applicatives en YAML et les restaure après fresh install.

```bash
# Créer le dossier de backup
mkdir -p backups

# Exporter les ressources applicatives (exclure namespaces système)
kubectl get all -A -o yaml | \
  grep -v 'namespace: kube-system' | \
  grep -v 'namespace: calico' | \
  grep -v 'namespace: kube-ingress' | \
  grep -v 'namespace: kube-monitoring' | \
  grep -v 'namespace: default' \
  > backups/resources-$(date +%Y%m%d).yaml

# OU exporter sélectivement par namespace applicatif :
for ns in mon-app1 mon-app2; do
    kubectl get all -n $ns -o yaml >> backups/resources-$(date +%Y%m%d).yaml
done
```

Pour restaurer (après fresh install) :
```bash
kubectl apply -f backups/resources-AAAAMMJJ.yaml
```

**Note** : Les ressources dans `default` namespace (comme test-pod) sont exclues par défaut. Ajouter `--namespace=default` si nécessaire.

Pour plus de détails sur les autres méthodes testées et leurs limitations, voir [ANALYSE_SNAPSHOT_RESTORE.md](./ANALYSE_SNAPSHOT_RESTORE.md).

### Pour un usage quotidien

```bash
# Arrêter le cluster
vagrant suspend

# Reprendre plus tard
vagrant resume
```

---

## Références

- Documentation originale : https://kanops.io/blog/deployer-cluster-kubernetes-local-vagrant
- Repository GitHub : https://github.com/kanops/k8s_vagrant
- Configuration multi-clusters : https://kubernetes.io/fr/docs/tasks/access-application-cluster/configure-access-multiple-clusters/
- Retour d'expérience backup/restore : [docs/ANALYSE_SNAPSHOT_RESTORE.md](./docs/ANALYSE_SNAPSHOT_RESTORE.md)
- Tests Velero : [docs/ANALYSE_VELERO.md](./docs/ANALYSE_VELERO.md)
