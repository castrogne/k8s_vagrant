#!/bin/bash

# Enhanced join with connectivity check and retry
MAX_RETRIES=3
RETRY_DELAY=10

echo "🔄 Checking control-plane connectivity..."
for i in $(seq 1 $MAX_RETRIES); do
    if ssh -i /home/vagrant/.ssh/id_rsa -o "StrictHostKeyChecking=no" -o "ConnectTimeout=10" vagrant@192.168.56.11 "echo 'OK'" >/dev/null 2>&1; then
        echo "✅ Control-plane is reachable (attempt $i/$MAX_RETRIES)"
        break
    else
        echo "⏳ Waiting for control-plane... (attempt $i/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    fi
done

if [ $i -gt $MAX_RETRIES ]; then
    echo "❌ Failed to reach control-plane after $MAX_RETRIES attempts"
    exit 1
fi

echo "🔄 Waiting for control-plane to be fully ready..."
#sleep 15  # Extra wait for control-plane stability

echo "📦 Getting join command..."
JOIN_COMMAND=$(ssh -i /home/vagrant/.ssh/id_rsa -o "StrictHostKeyChecking=no" vagrant@192.168.56.11 "sudo kubeadm token create --print-join-command")
echo "🔗 Executing join command..."
sudo $JOIN_COMMAND
rm /home/vagrant/.ssh/id_rsa