see https://kanops.io/blog/deployer-cluster-kubernetes-local-vagrant
https://github.com/kanops/k8s_vagrant

0- Install kubectl and autocompletion
see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

1- Install Virtualbox with script install_virtualvox.sh (tested on Ubuntu 22.04)

2- vagrant up

3- Make Kubeconfig
```vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > Kubeconfig.yaml```

4- use the Kubeconfig
see https://kubernetes.io/fr/docs/tasks/access-application-cluster/configure-access-multiple-clusters/
```export KUBECONFIG=/home/ppaquin/Projets/perso/k8s_vagrant/Kubeconfig.yaml```

5- Restart vagrant with provisioner !
```vagrant up --provision```

6- Vérifier tout va bien : 
```kubectl get nodes -o wide```


Bugfixes : 
* "pod does not exist"
https://medium.com/@mukesh.yadav_86837/how-to-fix-error-unable-to-upgrade-connection-pod-does-not-exist-fa90b7d1e44b
https://medium.com/@kanrangsan/how-to-specify-internal-ip-for-kubernetes-worker-node-24790b2884fd

