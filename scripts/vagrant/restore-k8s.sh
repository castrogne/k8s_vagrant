#!/bin/bash
# Kubernetes Restore Script
# Restaure le cluster depuis un backup
# Usage: ./scripts/vagrant/restore-k8s.sh [backup-date]
# Exemple: ./scripts/vagrant/restore-k8s.sh 20260221_143000

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 [backup-date]"
    echo "Exemple: $0 20260221_143000"
    echo ""
    echo "Backups disponibles:"
    ls -la ./backups/ 2>/dev/null || echo "Aucun backup trouvé"
    exit 1
fi

BACKUP_DATE=$1
BACKUP_PATH="./backups/k8s-${BACKUP_DATE}"

echo "=========================================="
echo "🔄 Kubernetes Restore"
echo "=========================================="

if [ ! -d "$BACKUP_PATH" ]; then
    echo "❌ Backup non trouvé: $BACKUP_PATH"
    exit 1
fi

echo "📂 Backup: $BACKUP_PATH"
echo ""

# 1. Copier les fichiers vers control-plane
echo "📤 Transfert des fichiers..."
vagrant scp "${BACKUP_PATH}/etcd.tar.gz" control-plane1:/tmp/etcd.tar.gz
vagrant scp "${BACKUP_PATH}/pki.tar.gz" control-plane1:/tmp/pki.tar.gz

# 2. Arrêter kubelet
echo "🛑 Arrêt de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl stop kubelet"

# 3. Restaurer etcd
echo "📦 Restore etcd..."
vagrant ssh control-plane1 -c "sudo rm -rf /var/lib/etcd/*"
vagrant ssh control-plane1 -c "sudo tar -xzf /tmp/etcd.tar.gz -C /"

# 4. Restaurer PKI
echo "🔑 Restore PKI..."
vagrant ssh control-plane1 -c "sudo tar -xzf /tmp/pki.tar.gz -C /"

# 5. Redémarrer kubelet
echo "▶️ Redémarrage de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl restart kubelet"

echo ""
echo "✅ Restore terminé!"
echo ""
echo "⏳ Waiting for cluster to be ready..."
sleep 30

# 6. Vérifier
echo "🔍 Vérification..."
vagrant ssh control-plane1 -c "kubectl get nodes"
vagrant ssh control-plane1 -c "kubectl get pods -n kube-system"

echo "=========================================="
