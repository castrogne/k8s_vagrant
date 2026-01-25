#!/bin/bash

KUBE_VERSION="1.35"

# Deploy keys to allow all nodes to connect each others as vagrant
mv /tmp/id_rsa*  /home/vagrant/.ssh/

chmod 400 /home/vagrant/.ssh/id_rsa*
chown vagrant:  /home/vagrant/.ssh/id_rsa*

cat /home/vagrant/.ssh/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
chmod 400 /home/vagrant/.ssh/authorized_keys
chown vagrant: /home/vagrant/.ssh/authorized_keys

# Enable modules for containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Enable networking config for k8s
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Install containerd and dependencies
apt-get update && sudo apt-get install -y containerd apt-transport-https ca-certificates curl gnupg

# Disable swap
# Note: group 'containerd' doesn't exist, containerd runs as root
swapoff -a

# APT INSTALLATION - Use official repository for better stability
echo "📦 Installing Kubernetes ${KUBE_VERSION} via official repository..."

# Add k8s GPG key (using official working method)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring

# Add repository list (corrected format)
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list 

# Install k8s via APT
apt-get update && apt-get install -y kubelet kubeadm kubectl

# Disable auto-update
apt-mark hold kubelet kubeadm kubectl

echo "✅ Kubernetes ${KUBE_VERSION} installed via APT"

# Enable and start services
systemctl enable containerd
systemctl enable kubelet
echo "✅ Services enabled"

# Copy startup scripts
cp /tmp/start_k8s.sh /home/vagrant/start_k8s.sh
chmod +x /home/vagrant/start_k8s.sh
chown vagrant:vagrant /home/vagrant/start_k8s.sh

# Install systemd service
cp /tmp/k8s-startup.service /etc/systemd/system/k8s-startup.service
systemctl daemon-reload
systemctl enable k8s-startup.service