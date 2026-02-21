#!/bin/bash
# Kubernetes Backup Script
# Sauvegarde etcd + PKI pour upgrade ou restauration
# Usage: ./scripts/vagrant/backup-k8s.sh

set -e

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/k8s-${DATE}"

echo "=========================================="
echo "🔐 Kubernetes Backup"
echo "=========================================="

mkdir -p "$BACKUP_PATH"

# 1. Backup etcd (TOUT l'état du cluster)
echo "📦 Backup etcd..."
vagrant ssh control-plane1 -c "sudo tar -czf /tmp/etcd.tar.gz -C / var/lib/etcd"
vagrant scp control-plane1:/tmp/etcd.tar.gz "${BACKUP_PATH}/etcd.tar.gz"

# 2. Backup PKI (certificats)
echo "🔑 Backup PKI..."
vagrant ssh control-plane1 -c "sudo tar -czf /tmp/pki.tar.gz -C / etc/kubernetes/pki"
vagrant scp control-plane1:/tmp/pki.tar.gz "${BACKUP_PATH}/pki.tar.gz"

# 3. Créer MANIFEST
cat > "${BACKUP_PATH}/MANIFEST.txt" <<EOF
Kubernetes Backup - ${DATE}
========================
Contenu:
- etcd.tar.gz  : Base de données complète du cluster
- pki.tar.gz   : Certificats Kubernetes

Restore:
1. Extraire etcd.tar.gz vers /var/lib/etcd
2. Extraire pki.tar.gz vers /etc/kubernetes/
3. Redémarrer kubelet: systemctl restart kubelet
EOF

echo ""
echo "✅ Backup créé: ${BACKUP_PATH}"
ls -lh "${BACKUP_PATH}/"
echo "=========================================="
