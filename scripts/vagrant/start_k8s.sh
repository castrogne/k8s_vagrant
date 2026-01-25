#!/bin/bash

# Wait for network to be ready
sleep 10

# Start all required services
echo "Starting containerd and kubelet services..."
sudo systemctl start containerd
sudo systemctl start kubelet

# Verify kubelet is running
sleep 5
if sudo systemctl is-active --quiet kubelet; then
    echo "✅ Kubelet started successfully"
else
    echo "❌ Kubelet failed to start"
fi

# Wait for kubelet to be ready
sleep 20

# If this is control-plane1, check if cluster needs to be initialized
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" = "control-plane1" ]]; then
    # Check if kubeadm has already been run
    if [ ! -f /etc/kubernetes/admin.conf ]; then
        echo "Cluster not initialized, running kubeadm init..."
        sudo kubeadm init --pod-network-cidr 192.168.0.0/16 \
            --apiserver-advertise-address "192.168.56.11" \
            --control-plane-endpoint "192.168.56.11"
        
        # Copy kubeconfig to user workspace
        mkdir -p /home/vagrant/.kube
        sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
        sudo chown vagrant: /home/vagrant/.kube/config
    fi
fi

echo "Kubernetes services started successfully"