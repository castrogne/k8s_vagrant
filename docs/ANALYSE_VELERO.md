# Analyse Velero - Apprentissage pas-à-pas

## Objectif

Apprendre Velero pour backup/restore de clusters Kubernetes.

**Contexte** : Les méthodes précédentes (etcdctl snapshot, kubectl export) ont des limitations documentées dans [ANALYSE_SNAPSHOT_RESTORE.md](./ANALYSE_SNAPSHOT_RESTORE.md).

**Objectif final** : Réaliser un backup complet → destroy du cluster → reinstall → restore fonctionnel.

---

## Théorie macroscopique

### Architecture Velero

```
┌──────────────────┐     ┌───────────────────┐     ┌────────────────┐
│   Velero CLI     │────▶│   Velero Server   │────▶│  Object Store  │
│   (terminal)     │     │   (dans K8s)      │     │  (MinIO/S3)    │
└──────────────────┘     └───────────────────┘     └────────────────┘
```

**3 composants clés** :
- **Velero CLI** : Commandes utilisateur (`velero backup create...`)
- **Velero Server** : Pods dans K8s, lit l'API server, crée des CustomResources
- **Object Store** : Bucket S3/MinIO pour stocker les backups

### Pourquoi ça marche mieux que etcdctl ?

Velero n'accède **jamais à etcd**. Il utilise l'API Kubernetes comme un utilisateur normal :
1. Interroge l'API pour récupérer les ressources
2. Sérialise en JSON/YAML
3. Compresse et upload dans S3

→ Les IPs, certificats, configs système ne sont PAS restaurées (c'est le but).

### Providers de stockage

Velero supporte plusieurs providers pour le stockage des backups :

| Provider | Backend | Plugin | Notes |
|----------|---------|--------|-------|
| **aws** | AWS S3, MinIO, S3-compatible | `velero-plugin-for-aws` | ✅ Utilisé actuellement |
| **gcp** | Google Cloud Storage | `velero-plugin-for-gcp` | 5 GB gratuit |
| **azure** | Azure Blob Storage | `velero-plugin-for-azure` | Cloud Microsoft |
| **csi** | CSI Volume Snapshots | Inclus | Snapshot de volumes |

**Pourquoi `aws` fonctionne avec MinIO ?** Velero utilise le plugin AWS qui implémente l'API S3. MinIO implémente aussi l'API S3 → compatible.

### Comparaison MinIO vs Google Cloud Storage

| | MinIO | GCP Cloud Storage |
|---|-------|-------------------|
| Coût | Gratuit (local) | 5 GB gratuit (tiers gratuit GCP) |
| Persistance | **Volatile** (détruit avec le cluster) | ✅ Durable (cloud) |
| Complexité | Simple, "clé en main" | Moyenne (credentials GCP) |
| Accès externe | Nécessite exposition (NodePort/Ingress) | ✅ Via API Google |
| Usage local | ✅ | ⚠️ Requiert connexion internet |

**Conclusion** : MinIO = développement/test. GCP = backup qui survit à la destruction du cluster.

**Note** : Pour GCP, activer "Interoperability" dans les settings Cloud Storage et générer des clés HMAC.

---

## Plan des sessions

| Session | Objectif | Statut |
|---------|----------|--------|
| [Session 1](#session-1--installation) | Installation MinIO + Velero | ✅ Terminée |
| [Session 2](#session-2--backuprestore-simple) | Backup/restore simple sur même cluster | ✅ Terminée |
| [Session 3](#session-3--backup-avec-état) | Préparation : app réaliste + backup | ⏳ À faire |
| [Session 4](#session-4--destroy-up-restore) | Test complet destroy+restore | ⏳ À faire |

---

## Session 1 : Installation

### Objectif

Installer MinIO et Velero server sur le cluster.

### Commandes exécutées

#### 1. Installation Velero CLI

```bash
# Téléchargement Velero v1.18.0
curl -LO https://github.com/vmware-tanzu/velero/releases/download/v1.18.0/velero-v1.18.0-linux-amd64.tar.gz
tar -xzf velero-v1.18.0-linux-amd64.tar.gz
sudo mv velero-v1.18.0-linux-amd64/velero /usr/local/bin/
```

#### 2. Vérification

```bash
velero version
```

**Résultat attendu** :
```
Client: v1.18.0
Server: v1.18.0 (ou non installé si CLI uniquement)
```

#### 3. Déploiement MinIO

```bash
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/minio/00-minio-deployment.yaml
```

#### 4. Attendre que MinIO soit prêt

```bash
kubectl get pods -n velero
```

**Résultat attendu** :
- `minio-...` : **1/1 Running** (Deployment)
- `minio-setup-...` : **Completed** (Job, a terminé son travail)

Le Job n'est PAS un Deployment. Il fait son travail (créer le bucket) puis se termine. C'est normal.

#### 5. Installation Velero server

```bash
# Création du fichier credentials
cat > credentials-velero << 'EOF'
[default]
aws_access_key_id = minio
aws_secret_access_key = minio123
EOF

# Installation Velero
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000
```

**Note** : `--use-volume-snapshots=false` car MinIO ne gère pas les snapshots de volumes.

#### 6. Vérification

```bash
kubectl get pods -n velero
```

**Résultat attendu** : velero-xxx Running

### Problèmes rencontrés

**Aucun problème rencontré.**

### Vérifications post-installation

#### Vérification des pods

```bash
kubectl get pods -n velero
```

**Résultat** :
```
NAME                     READY   STATUS      RESTARTS   AGE
minio-b64c8445f-qx4df    1/1     Running     0          11m
minio-setup-9cr8k        0/1     Completed   0          11m
velero-6bf59d689-b8xnn   1/1     Running     0          4m25s
```

Tous les composants sont opérationnels.

#### Vérification du BackupStorageLocation

```bash
kubectl get backupstoragelocation -n velero
```

**Résultat** :
```
NAME      PHASE       LAST VALIDATED   AGE     DEFAULT
default   Available   48s              5m27s   true
```

**Explication du BackupStorageLocation** :

| Champ | Signification |
|-------|--------------|
| `default` | Nom du location (il peut y en avoir plusieurs) |
| `Available` | ✅ Velero peut se connecter à MinIO et écrire/lire |
| `LAST VALIDATED` | Dernière vérification de connexion (48s) |
| `DEFAULT` | true = c'est le location par défaut utilisé pour les backups |

Le status `Available` confirme que le lien Velero ↔ MinIO fonctionne correctement.

#### Vérification des backups

```bash
velero backup get
```

**Résultat** : (vide)

**Conclusion** : Aucun backup créé, c'est normal. Velero est prêt.

---

## Session 2 : Backup/Restore simple

### Objectif

Premier backup/restore sur le même cluster.

### Commandes exécutées

#### 1. Déployer l'app de test (nginx-app)

```bash
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/nginx-app/base.yaml
```

#### 2. Vérifier le déploiement

```bash
kubectl get all -n nginx-example
```

#### 3. Créer un backup

```bash
velero backup create nginx-backup --selector app=nginx
```

#### 4. Vérifier le statut

```bash
velero backup get
velero backup describe nginx-backup
```

#### 5. Supprimer l'app

```bash
kubectl delete namespace nginx-example
```

#### 6. Restaurer

```bash
velero restore create --from-backup nginx-backup
```

#### 7. Vérifier le restore

```bash
kubectl get all -n nginx-example
```

### Problèmes rencontrés

**Aucun problème rencontré.**

---

## Session 3 : Backup avec état

### Objectif

Créer une application "réaliste" (Deployment + ConfigMap + Service) et faire un backup complet.

### Application de test

```yaml
# À déployer
apiVersion: v1
kind: Namespace
metadata:
  name: demo-app
---
# Deployment avec ConfigMap
# Service
```

### Commandes exécutées

#### 1. Déployer l'application

```bash
kubectl apply -f demo-app.yaml
```

#### 2. Créer le backup

```bash
velero backup create demo-backup --include-namespaces demo-app
```

#### 3. Vérifier le backup

```bash
velero backup describe demo-backup
```

### Problèmes rencontrés

[À documenter]

---

## Session 4 : Destroy + Up + Restore complet

### Objectif

Test ultime : détruire le cluster, le recréer, et restaurer le backup.

### Danger ⚠️

Cette session **détruit** le cluster Vagrant. Prévoir ~15-20 minutes.

### Commandes exécutées

#### 1. Vérifier que le backup existe

```bash
velero backup get
```

#### 2. Exporter le kubeconfig

```bash
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig-backup.yaml
```

#### 3. Backup final (par sécurité)

```bash
velero backup create final-backup --include-namespaces demo-app
```

#### 4. Détruire le cluster

```bash
vagrant destroy -f
```

#### 5. Recréer le cluster

```bash
vagrant up --provision
```

**⏳ Attendre 10-15 minutes**

#### 6. Réinstaller Calico

```bash
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
```

#### 7. Réinstaller Velero

```bash
# Réappliquer MinIO
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/minio/00-minio-deployment.yaml

# Recréer credentials
cat > credentials-velero << 'EOF'
[default]
aws_access_key_id = minio
aws_secret_access_key = minio123
EOF

# Réinstaller Velero server
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000
```

#### 8. Vérifier Velero

```bash
kubectl get pods -n velero
velero backup get
```

**Note** : Les backups sont dans MinIO qui est... détruit. Il faudra une solution de stockage persistante pour ce test.

#### 9. Restore (si stockage persistante disponible)

```bash
velero restore create --from-backup demo-backup
```

#### 10. Vérifier

```bash
kubectl get all -n demo-app
```

### Problèmes rencontrés

[À documenter]

---

## Notes et observations

### Observations

[À documenter pendant les sessions]

### Commandes Velero utiles

| Commande | Usage |
|----------|-------|
| `velero backup create <nom>` | Créer un backup |
| `velero backup get` | Lister les backups |
| `velero restore create --from-backup <nom>` | Restaurer |
| `velero restore get` | Lister les restores |
| `velero schedule create --schedule "0 1 * * *"` | Backup planifié (cron) |
| `velero describe <nom>` | Détails backup/restore |
| `velero logs <nom>` | Logs backup/restore |

### Filtrage des ressources

```bash
# Backup par namespace
velero backup create backup-ns --include-namespaces mon-namespace

# Backup par selector
velero backup create backup-sel --selector tier=production

# Exclure des ressources
velero backup create backup-excl --selector 'backup notin (ignore)'
```

---

## Conclusions

[À remplir après les sessions]

### Ce qui fonctionne

[À documenter]

### Ce qui ne fonctionne pas

[À documenter]

### Points à explorer

- [ ] Stockage persistante (MinIO avec PVC ?)
- [ ] Backup planifié (schedule)
- [ ] Backup de volumes persistants (PVC)
- [ ] Migration vers autre cluster

---

## Remarques

### Session 1 : RBAC et ServiceAccount

**Observation** : `velero install` utilise le kubeconfig utilisateur courant 
(via `~/.kube/config`), sans créer de ServiceAccount dédié.

**Pattern production recommandé :**

```bash
# 1. Créer un ServiceAccount dédié
kubectl create serviceaccount velero -n velero

# 2. Créer ClusterRole avec droits minimaux
kubectl apply -f - << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: velero
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: velero
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: velero
subjects:
- kind: ServiceAccount
  name: velero
  namespace: velero
EOF
```

**Principe** : Principe du moindre privilège - le compte Velero n'a que 
les droits nécessaires, pas les droits admin.

**Note** : En dev/test, utiliser le kubeconfig utilisateur est acceptable.

### Session 2 : Commandes de backup

**Observation** : Velero permet debacker plusieurs namespaces ou par label.

#### Backup multi-namespaces

```bash
# Un seul backup pour plusieurs namespaces
velero backup create backup-multi --include-namespaces nginx-example,default

# Backup de tous les namespaces (sauf système)
velero backup create backup-full --exclude-namespaces kube-system,kube-public,kube-ingress,kube-node-lease,velero,calico-system
```

#### Backup par label

```bash
# Backup avec selector (OR logique)
velero backup create backup-sel --selector 'app=nginx || app=test-pod'

# Backup en excluant par label
velero backup create backup-excl --selector 'backup notin (ignore)'
```

**Note** : Pourbacker un pod sans label, ajouter un label temporaire :
```bash
kubectl label pod <nom> -n default backup=true
velero backup create backup --selector 'backup=true'
kubectl label pod <nom> -n default backup-  # nettoyer après
```

---

## Références

- [Velero Docs](https://velero.io/docs/main/)
- [Velero on GitHub](https://github.com/vmware-tanzu/velero)
- [MinIO Evaluation Install](https://velero.io/docs/main/contributions/minio/)
- [Disaster Recovery](https://velero.io/docs/main/disaster-case/)
