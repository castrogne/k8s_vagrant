# Mise en place d'un cluster Kubernetes en local avec *Vagrant*

## Stack
- Vagrant 2.3.4
- Virtual Box 7.0.4
- Ubuntu 22.04 LTS
- Kubernetes 1.29.9

## Post - déploiement
- Installer *vagrant*
- Installer *Virtual Box*

## Configuration
- **Important** : Le projet utilise maintenant Ubuntu 22.04 LTS et Kubernetes 1.29.9 avec les nouveaux dépôts communautaires pkgs.k8s.io.
- La version de **Kubernetes** peut être modifiée grâce à la variable ```KUBE_VERSION``` dans le fichier ```./scripts/vagrant/init_k8s.sh```
- Modifier les clés de configurations ```NMB_CONTROL_PLANE``` et ```NMB_WORKER``` dans le fichier **Vagrantfile** selon la configuration que vous voulez mettre en place.

## Déploiement
Pour déployer le cluster, se rendre dans le répertoire où se trouve le **Vagrantfile**, puis exécuter la commande:
```bash
    vagrant up --provision
```

⏳ Attendre quelques minutes le temps que les VMs soit créer et provisionner, cela dépendra du débit de votre connexion à Internet ainsi que les performances de votre machine.

**Note** : Tous les scripts de configuration sont dans le répertoire `./scripts/vagrant/`. L'infrastructure utilise maintenant containerd au lieu de Docker pour une meilleure compatibilité avec Kubernetes 1.29.

## Accès au cluster
- Une fois le cluster déployé, il faudra récupérer le fichier ```kubeconfig``` permettant d'interagir avec notre cluster:
  ```bash
    # Récupérer le kubeconfig à la racine du projet
    vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig.yaml
  ```
- Configurez l'accès au cluster de manière permanente :
  ```bash
    # Ajouter à votre .bashrc (adapter le chemin)
    export KUBECONFIG=$HOME/Projets/perso/k8s_vagrant/kubeconfig.yaml
    
    # Ou utiliser temporairement dans la session
    export KUBECONFIG=$PWD/kubeconfig.yaml
  ```
  **Note** : Vous devez avoir `kubectl` d'installé sur votre machine locale.
- Avant de pouvoir utiliser notre cluster, il faudra auparavant installer un plugin k8s pour le réseau. Ici [Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/) sera utilisé. Pour le déployer:
  ```bash
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
  ```
- Ci-dessous, notre cluster disponible et prêt à accueillir les applications:
  ![cluster_up.png](https://media.kanops.io/blog/img/k8s_vagrant/cluster_up.png)

## Workflow complet

Pour la procédure d'installation et d'utilisation complète avec les snapshots, consultez le [HOWTO.md](./HOWTO.md).

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

Si le problème persiste, redémarrez votre machine et réessayez.