#!/bin/bash
# Kubernetes Restore Script
# Restaure le cluster depuis un backup etcdctl snapshot
# Usage: ./scripts/vagrant/restore-k8s.sh [backup-date]
# Exemple: ./scripts/vagrant/restore-k8s.sh 20260322_111009
#
# IMPORTANT: Ce restore fonctionne uniquement sur le MÊME cluster
# (mêmes certificats PKI)

BACKUP_DATE=$1
BACKUP_PATH="./backups/k8s-${BACKUP_DATE}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

echo "=========================================="
echo "Kubernetes Restore (etcdctl snapshot)"
echo "=========================================="

if [ -z "$1" ]; then
    echo "Usage: $0 [backup-date]"
    echo "Exemple: $0 20260322_111009"
    echo ""
    echo "Backups disponibles:"
    ls -la ./backups/ 2>/dev/null || echo "Aucun backup trouvé"
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    error "Backup non trouvé: $BACKUP_PATH"
    ls ./backups/ 2>/dev/null
    exit 1
fi

log "Backup: $BACKUP_PATH"

if [ -f "${BACKUP_PATH}/etcd-snapshot.db.gz" ]; then
    log "Décompression du snapshot..."
    gunzip -c "${BACKUP_PATH}/etcd-snapshot.db.gz" > "${BACKUP_PATH}/etcd-snapshot.db"
elif [ -f "${BACKUP_PATH}/etcd-snapshot.db" ]; then
    log "Snapshot déjà décompressé"
else
    error "Fichier snapshot non trouvé"
    ls "${BACKUP_PATH}/"
    exit 1
fi

log "Installation de etcdutl si nécessaire..."
vagrant ssh control-plane1 -c 'cat > /tmp/install_etcdutl.sh << '"'"'SCRIPT'"'"'
#!/bin/bash
mkdir -p /home/vagrant/.local/bin
if ! command -v /home/vagrant/.local/bin/etcdutl &> /dev/null; then
    echo "Installation de etcdutl..."
    ETCD_VER="v3.5.15"
    curl -sL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" -o /tmp/etcd.tar.gz
    tar xzf /tmp/etcd.tar.gz -C /tmp --strip-components=1
    cp /tmp/etcdctl /home/vagrant/.local/bin/
    cp /tmp/etcdutl /home/vagrant/.local/bin/
    rm -rf /tmp/etcd.tar.gz /tmp/etcd-${ETCD_VER}-linux-amd64
    echo "etcdutl installé dans /home/vagrant/.local/bin"
else
    echo "etcdutl déjà présent"
fi
SCRIPT
chmod +x /tmp/install_etcdutl.sh
/tmp/install_etcdutl.sh' 2>&1

log "Transfert du snapshot vers le control-plane..."
vagrant scp "${BACKUP_PATH}/etcd-snapshot.db" control-plane1:/home/vagrant/etcd-snapshot.db

log "Déplacement vers /tmp/ avec permissions..."
vagrant ssh control-plane1 -c "sudo mv /home/vagrant/etcd-snapshot.db /tmp/etcd-snapshot.db && sudo chmod 644 /tmp/etcd-snapshot.db"

log "Arrêt de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl stop kubelet" 2>/dev/null || true
sleep 2

log "Déplacement des static pods..."
vagrant ssh control-plane1 -c "sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ 2>/dev/null || true"
vagrant ssh control-plane1 -c "sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/ 2>/dev/null || true"
sleep 2

log "Suppression de l'ancien répertoire etcd..."
vagrant ssh control-plane1 -c "sudo rm -rf /var/lib/etcd"

log "Restauration du snapshot etcd..."
vagrant ssh control-plane1 -c "export PATH=\$PATH:/home/vagrant/.local/bin && sudo ETCDCTL_API=3 etcdutl snapshot restore /tmp/etcd-snapshot.db \
    --data-dir=/var/lib/etcd \
    --name=control-plane1 \
    --initial-cluster=control-plane1=https://10.0.10.11:2380 \
    --initial-advertise-peer-urls=https://10.0.10.11:2380"

log "Restauration des permissions..."
vagrant ssh control-plane1 -c "sudo chown -R root:root /var/lib/etcd"

log "Restauration des static pods..."
vagrant ssh control-plane1 -c "sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/ 2>/dev/null || true"
vagrant ssh control-plane1 -c "sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/ 2>/dev/null || true"
sleep 3

log "Démarrage de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl start kubelet" 2>/dev/null || true
sleep 5

log "Vérification kubelet..."
KUBELET_AFTER=$(vagrant ssh control-plane1 -c "sudo systemctl is-active kubelet" 2>/dev/null | tr -d '\n\r')
log "kubelet: $KUBELET_AFTER"

log "Nettoyage des fichiers temporaires..."
vagrant ssh control-plane1 -c "sudo rm -f /tmp/etcd-snapshot.db"
rm -f "${BACKUP_PATH}/etcd-snapshot.db"

echo ""
echo "=========================================="
log "Restore terminé!"
log "Vérifiez le cluster avec: kubectl get pods"
log "Attendez quelques minutes pour que les pods redémarrent"
echo "=========================================="
