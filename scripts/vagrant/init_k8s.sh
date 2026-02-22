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

# =============================================
# MANUAL INSTALLATION OF CONTAINERD 2.x
# =============================================
echo "=========================================="
echo "🔧 Step 1: Installing containerd 2.x manually"
echo "=========================================="

# Disable swap
swapoff -a

# Install dependencies
echo "📦 Installing dependencies..."
apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg wget

# Download and install containerd 2.x
echo "⬇️ Downloading containerd 2.0.2..."
cd /tmp
wget --progress=dot:giga https://github.com/containerd/containerd/releases/download/v2.0.2/containerd-2.0.2-linux-amd64.tar.gz
if [ $? -ne 0 ]; then
    echo "❌ Failed to download containerd 2.0.2"
    exit 1
fi
echo "📂 Extracting containerd..."
tar -C /usr/local -xzf containerd-2.0.2-linux-amd64.tar.gz
if [ $? -ne 0 ]; then
    echo "❌ Failed to extract containerd"
    exit 1
fi
echo "✅ containerd 2.0.2 installed"

# Download and install runc
echo "⬇️ Downloading runc..."
wget --progress=dot:giga https://github.com/opencontainers/runc/releases/download/v1.2.0/runc.amd64
if [ $? -ne 0 ]; then
    echo "❌ Failed to download runc"
    exit 1
fi
echo "📂 Installing runc..."
install -m 755 runc.amd64 /usr/local/sbin/runc
echo "✅ runc installed"

# Download and install CNI plugins
echo "⬇️ Downloading CNI plugins..."
mkdir -p /opt/cni/bin
wget --progress=dot:giga https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
if [ $? -ne 0 ]; then
    echo "❌ Failed to download CNI plugins"
    exit 1
fi
echo "📂 Extracting CNI plugins..."
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.4.0.tgz
echo "✅ CNI plugins installed"

# Configure containerd
echo "⚙️ Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

echo "✅ Containerd 2.0.2 configured successfully"
echo "=========================================="
echo "🔧 Step 2: Installing Kubernetes ${KUBE_VERSION}"
echo "=========================================="

# APT INSTALLATION - Use official repository for better stability
echo "📦 Installing Kubernetes ${KUBE_VERSION} via official repository..."

# Add k8s GPG key (using official working method)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring

# Add repository list (corrected format)
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list 

# Install k8s via APT
echo "⬇️ Installing Kubernetes packages..."
apt-get update && apt-get install -y kubelet kubeadm kubectl

if [ $? -ne 0 ]; then
    echo "❌ Failed to install Kubernetes packages"
    exit 1
fi

# Disable auto-update
apt-mark hold kubelet kubeadm kubectl

echo "✅ Kubernetes ${KUBE_VERSION} installed via APT"

# Enable and start services
echo "🔄 Enabling containerd service..."
# Create systemd service for containerd if not exists
cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStart=/usr/local/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable containerd

# =============================================
# Fix: Configure kubelet with correct node IP
# =============================================
echo "🔧 Configuring kubelet with correct node IP..."

# Detect internal network IP (10.0.10.x) for VM↔VM communication
PRIVATE_IP=$(ip -4 addr show | grep "10.0.10" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# Fallback: detect host-only network IP (192.168.56.x)
if [ -z "$PRIVATE_IP" ]; then
    PRIVATE_IP=$(ip -4 addr show | grep "192.168.56" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi

if [ -z "$PRIVATE_IP" ]; then
    echo "⚠️ Could not detect private IP, using hostname-based fallback..."
    # Fallback: use hostname to determine IP based on Vagrantfile config
    case $(hostname) in
        control-plane*) PRIVATE_IP="10.0.10.1$(hostname | grep -oP '\d+$')" ;;
        worker*) PRIVATE_IP="10.0.10.2$(hostname | grep -oP '\d+$')" ;;
    esac
fi

if [ -n "$PRIVATE_IP" ]; then
    echo "📌 Setting node IP to: $PRIVATE_IP"
    echo "KUBELET_EXTRA_ARGS=--node-ip=$PRIVATE_IP" | sudo tee /etc/default/kubelet
else
    echo "❌ Failed to determine node IP"
fi

systemctl enable kubelet

echo "🔄 Starting containerd service..."
systemctl start containerd
sleep 2
if systemctl is-active --quiet containerd; then
    echo "✅ containerd service started successfully"
else
    echo "❌ containerd service failed to start"
    systemctl status containerd
    exit 1
fi
echo "✅ Services enabled"

# Copy startup scripts
cp /tmp/start_k8s.sh /home/vagrant/start_k8s.sh
chmod +x /home/vagrant/start_k8s.sh
chown vagrant:vagrant /home/vagrant/start_k8s.sh

# Install systemd service
cp /tmp/k8s-startup.service /etc/systemd/system/k8s-startup.service
systemctl daemon-reload
systemctl enable k8s-startup.service