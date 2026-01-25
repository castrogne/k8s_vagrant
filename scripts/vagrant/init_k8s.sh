#!/bin/bash

KUBE_VERSION="1.29.9-1.1"

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
apt-get update && sudo apt-get install -y containerd.io apt-transport-https curl

# Disable swap
usermod -aG containerd vagrant
swapoff -a

# MANUAL INSTALLATION - Download packages directly to avoid repository issues
echo "📦 Downloading Kubernetes ${KUBE_VERSION} packages manually (bypassing repository issues)..."

# Download the exact versions
cd /tmp
curl -fsSL -O "https://dl.k8s.io/release/v1.29.9/binaries/linux/amd64/kubelet"
curl -fsSL -O "https://dl.k8s.io/release/v1.29.9/binaries/linux/amd64/kubeadm"  
curl -fsSL -O "https://dl.k8s.io/release/v1.29.9/binaries/linux/amd64/kubectl"

# Install k8s manually
chmod +x /tmp/kubelet /tmp/kubeadm /tmp/kubectl
sudo mv /tmp/kubelet /usr/local/bin/
sudo mv /tmp/kubeadm /usr/local/bin/
sudo mv /tmp/kubectl /usr/local/bin/

# Create symlinks for compatibility
sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
sudo ln -sf /usr/local/bin/kubeadm /usr/bin/kubeadm
sudo ln -sf /usr/local/bin/kubelet /usr/bin/kubelet

echo "Kubernetes ${KUBE_VERSION} installed manually"

# Disable auto-update
apt-mark hold kubelet kubeadm kubectl

# Enable and start services
systemctl enable containerd
systemctl enable kubelet

# Copy startup scripts
cp /tmp/start_k8s.sh /home/vagrant/start_k8s.sh
chmod +x /home/vagrant/start_k8s.sh
chown vagrant:vagrant /home/vagrant/start_k8s.sh

# Install systemd service
cp /tmp/k8s-startup.service /etc/systemd/system/k8s-startup.service
systemctl daemon-reload
systemctl enable k8s-startup.service