#!/bin/bash
# Kubernetes Backup Script
# Sauvegarde etcd (snapshot) pour upgrade ou restauration
# Usage: ./backup-k8s.sh
# 
# IMPORTANT: Cette méthode utilise etcdctl snapshot save qui crée un snapshot
# cohérent de la base etcd. Le restore fonctionne uniquement sur le MÊME cluster.

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/k8s-${DATE}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

echo "=========================================="
echo "Kubernetes Backup (etcdctl snapshot)"
echo "=========================================="

mkdir -p "$BACKUP_PATH"

log "Installation de etcdctl si nécessaire..."
vagrant ssh control-plane1 -c 'cat > /tmp/install_etcdctl.sh << '"'"'SCRIPT'"'"'
#!/bin/bash
mkdir -p /home/vagrant/.local/bin
if ! command -v /home/vagrant/.local/bin/etcdctl &> /dev/null; then
    echo "Installation de etcdctl..."
    ETCD_VER="v3.5.15"
    curl -sL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" -o /tmp/etcd.tar.gz
    tar xzf /tmp/etcd.tar.gz -C /tmp --strip-components=1
    cp /tmp/etcdctl /home/vagrant/.local/bin/
    cp /tmp/etcdutl /home/vagrant/.local/bin/
    rm -rf /tmp/etcd.tar.gz /tmp/etcd-${ETCD_VER}-linux-amd64
    echo "etcdctl installé dans /home/vagrant/.local/bin"
else
    echo "etcdctl déjà présent"
fi
SCRIPT
chmod +x /tmp/install_etcdctl.sh
/tmp/install_etcdctl.sh' 2>&1

log "Arrêt de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl stop kubelet" 2>/dev/null || true
sleep 2

log "Arrêt de kube-apiserver (static pod)..."
vagrant ssh control-plane1 -c "sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ 2>/dev/null || true"
sleep 2

log "Création du snapshot etcd..."
SNAPSHOT_RESULT=$(vagrant ssh control-plane1 -c "export PATH=\$PATH:/home/vagrant/.local/bin && sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snapshot.db \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key" 2>&1)
echo "$SNAPSHOT_RESULT"

if echo "$SNAPSHOT_RESULT" | grep -q "Error\|error\|failed"; then
    error "Échec de la création du snapshot etcd"
    vagrant ssh control-plane1 -c "sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/ 2>/dev/null || true"
    vagrant ssh control-plane1 -c "sudo systemctl start kubelet" 2>/dev/null || true
    exit 1
fi

log "Correction des permissions du snapshot..."
vagrant ssh control-plane1 -c "sudo chmod 644 /tmp/etcd-snapshot.db"

log "Restauration de kube-apiserver..."
vagrant ssh control-plane1 -c "sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/ 2>/dev/null || true"
sleep 2

log "Démarrage de kubelet..."
vagrant ssh control-plane1 -c "sudo systemctl start kubelet" 2>/dev/null || true
sleep 5

log "Vérification kubelet..."
KUBELET_AFTER=$(vagrant ssh control-plane1 -c "sudo systemctl is-active kubelet" 2>/dev/null | tr -d '\n\r')
log "kubelet: $KUBELET_AFTER"

log "Transfert du snapshot vers la machine locale..."
vagrant scp control-plane1:/tmp/etcd-snapshot.db "${BACKUP_PATH}/etcd-snapshot.db"

log "Compression du snapshot..."
gzip "${BACKUP_PATH}/etcd-snapshot.db"

log "Nettoyage des fichiers temporaires sur le control-plane..."
vagrant ssh control-plane1 -c "sudo rm -f /tmp/etcd-snapshot.db"

cat > "${BACKUP_PATH}/MANIFEST.txt" <<EOF
Kubernetes Backup (etcdctl) - ${DATE}
=======================
Contenu:
- etcd-snapshot.db.gz : Snapshot cohérent de la base etcd

IMPORTANT:
- Ce backup utilise etcdctl snapshot save pour un état cohérent
- Le restore fonctionne UNIQUEMENT sur le MÊME cluster
- Après destroy+up, les certificats seront différents → restore impossible

Restore (sur même cluster):
1. ./restore-k8s.sh ${DATE}
2. Vérifier: kubectl get pods
EOF

echo ""
echo "=========================================="
log "Backup créé: ${BACKUP_PATH}"
ls -lh "${BACKUP_PATH}/"
echo "=========================================="
