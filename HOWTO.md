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

Quick install all : (from scripts folder)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
k create ns kube-monitoring
k create ns kube-ingress
helm -n kube-ingress upgrade --install kube-ingress ingress-nginx/ingress-nginx -f helm/kube-ingress/ingress-nginx.yml --version 4.7.1
kubectl apply -n kube-ingress -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.crds.yaml
helm -n kube-ingress upgrade --install cert-manager jetstack/cert-manager -f helm/kube-ingress/cert-manager.yml --version 1.13.1
helm upgrade --install --set 'args={--kubelet-insecure-tls}' --namespace kube-system metrics-server metrics-server/metrics-server
helm -n kube-monitoring upgrade --install prometheus prometheus-community/kube-prometheus-stack -f helm/kube-monitoring/kube-prometheus-stack.yml --version 55.5.1

