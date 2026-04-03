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
| [Session 3](#session-3--backup-avec-état) | Backup avec ConfigMap + Service | ✅ Terminée |
| [Session 4](#session-4--destroy-up-restore-avec-gcp) | Test complet destroy+restore avec GCP | ✅ Terminée |

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

**Aucun problème rencontré.**

---

## Session 4 : Destroy + Up + Restore avec GCP

### Objectif

Test ultime : détruire le cluster, le recréer, et restaurer le backup depuis GCP Cloud Storage.

**Différence avec MinIO** : Les backups sont stockés dans le cloud, ils survivent à la destruction du cluster.

### Danger ⚠️

Cette session **détruit** le cluster Vagrant. Prévoir ~15-20 minutes.

### Prérequis GCP (à faire avant)

1. Créer un bucket GCP Cloud Storage (ex: `velero-backups-<id>`)
2. Activer Interoperability dans GCP Console → Storage → Settings → Interoperability
3. Générer des clés HMAC (Storage → Settings → Interoperability → Create a key)
4. Noter l'Access Key et le Secret Key

### Commandes exécutées

#### 1. Vérifier que le backup existe

```bash
velero backup get
```

#### 2. Exporter le kubeconfig (par sécurité)

```bash
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > ./kubeconfig-backup.yaml
```

#### 3. Backup final

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

#### 7. Réinstaller Velero avec GCP

**Option A : GCP avec Interoperability (clés HMAC au format AWS)**

Cette option utilise les clés HMAC créées pour l'accès interopérable S3.

```bash
# Créer les credentials GCP (format AWS S3)
cat > credentials-gcp << 'EOF'
[default]
aws_access_key_id = <TA_CLE_ACCESS>
aws_secret_access_key = <TON_SECRET>
EOF

# Réinstaller Velero avec le provider AWS (qui parle S3 à GCP)
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.2 \
    --bucket k8s_vagrant_velero \
    --secret-file ./credentials-gcp \
    --use-volume-snapshots=false \
    --backup-location-config region=us-east1,s3ForcePathStyle="true",s3Url=https://storage.googleapis.com
```

**Note** : Nécessite d'activer "Interoperability" dans GCP Console. Utiliser impérativement la version v1.8.2 du plugin (v1.9+ casse la compatibilité S3 tierce).

---

**Option B : GCP natif (fichier JSON Service Account)** ✅ Recommandé

Cette option utilise le fichier JSON du compte de service Google.

```bash
# 1. Télécharger le fichier JSON du compte de service
# GCP Console → IAM → Comptes de service → Clés → Créer une clé JSON

# 2. Réinstaller Velero avec le provider GCP
velero install \
    --provider gcp \
    --plugins velero/velero-plugin-for-gcp:v1.12.0 \
    --bucket <NOM_BUCKET> \
    --secret-file ./chemin/vers/velero-sa-key.json \
    --use-volume-snapshots=false
```

**Note** : Pas besoin d'Interoperability. Utilise les credentials Google natifs.

#### 8. Vérifier Velero et les backups

```bash
kubectl get pods -n velero
velero backup get
```

Les backups créés précédemment avec MinIO ne seront pas visibles (stockage différent). Un nouveau backup est nécessaire.

#### 9. Créer un backup dans GCP

```bash
# Backup de plusieurs namespaces
velero backup create gcp-backup --include-namespaces demo-app,default
```

#### 10. Vérifier le backup

```bash
# Le backup apparaît après ~1 minute (sync périodique)
velero backup get
kubectl get backupstoragelocation -n velero
```

#### 11. Vérifier dans GCP Console

Aller dans GCP Console → Cloud Storage → Bucket → Les fichiers de backup doivent apparaître.

#### 12. Restore

```bash
velero restore create --from-backup gcp-backup
```

#### 13. Vérifier

```bash
kubectl get all -n demo-app
```

---

### Résumé Session 4

**Commandes de backup/restore validées :**

```bash
# Backup (avant destroy)
velero backup create gcp-backup --include-namespaces demo-app,default

# Restore (après recreation du cluster)
velero restore create --from-backup gcp-backup

# Vérification
velero backup get
kubectl get all -n demo-app
```

**Résultat :** ✅ Backup survives au destroy du cluster, restore fonctionnel depuis GCP.

### Problèmes rencontrés

**Problème 1** : `velero install` avec GCP ne remplace pas le BackupStorageLocation existant (MinIO). 
Le message "already exists" a été ignoré.

**Solution** : Supprimer l'ancien BackupStorageLocation, MinIO, puis créer le nouveau BSL GCP.

```bash
# Supprimer l'ancien BackupStorageLocation MinIO
kubectl delete backupstoragelocation default -n velero

# ATTENTION : Le YAML MinIO inclut le namespace velero !
# Supprimer le YAML MinIO SUPPRIME LE NAMESPACE ENTIER (y compris Velero)
kubectl delete -f https://raw.githubusercontent.com/vmware-tanzu/velero/main/examples/minio/00-minio-deployment.yaml
```

**Problème 2** : Suppression du namespace velero bloquée.

Le namespace reste en "Terminating" à cause de restores et CRDs persistants.

**Solution** : Supprimer les CRDs Velero.

```bash
kubectl delete crds \
  backups.velero.io \
  backupstoragelocations.velero.io \
  restores.velero.io \
  schedules.velero.io \
  serverstatusrequests.velero.io \
  volumesnapshotlocations.velero.io \
  podvolumebackups.velero.io \
  podvolumerestores.velero.io \
  deletebackuprequests.velero.io \
  downloadrequests.velero.io \
  backuprepositories.velero.io \
  datadownloads.velero.io \
  datauploads.velero.io
```

**Problème 3** : Désinstallation complète de Velero.

Le namespace peut rester bloqué en "Terminating" si les CRDs ne sont pas supprimés en premier.

**Solution** : Supprimer les CRDs avant le namespace.

```bash
# 1. Supprimer les CRDs (supprime aussi les ressources)
kubectl delete crds \
  backuprepositories.velero.io \
  backups.velero.io \
  backupstoragelocations.velero.io \
  deletebackuprequests.velero.io \
  downloadrequests.velero.io \
  podvolumebackups.velero.io \
  podvolumerestores.velero.io \
  restores.velero.io \
  schedules.velero.io \
  serverstatusrequests.velero.io \
  volumesnapshotlocations.velero.io \
  datadownloads.velero.io \
  datauploads.velero.io

# 2. Supprimer le namespace
kubectl delete namespace velero

# 3. Vérifier
kubectl get crds | grep velero  # Ne doit rien retourner
kubectl get ns | grep velero     # Ne doit rien retourner
```

**Ordre IMPORTANT** : CRDs AVANT namespace.

---

**Problème 4** : Plugin AWS v1.9+ incompatible avec GCP Interoperability (HMAC keys).

**Symptôme** : `SignatureDoesNotMatch: Access denied` même avec les bonnes credentials.

**Cause** : Le plugin AWS de Velero a changé le mécanisme de signature AWS SDK en v1.9+, ce qui a cassé la compatibilité avec les systèmes S3 tierces (GCP, IBM COS, Backblaze, etc.).

**Solution** : Utiliser impérativement la version v1.8.2 du plugin AWS :
```bash
--plugins velero/velero-plugin-for-aws:v1.8.2
```

**Source** : [Velero AWS Plugin and SignatureDoesNotMatch nonsense](https://scaleoutsean.github.io/2024/07/13/velero-aws-plugin-s3-signature-does-not-match-nonsense.html)

---

### Commandes pour installation Velero avec GCP (après destroy+up)

**Option A : GCP avec Interoperability**

```bash
# 1. Vérifier que kubectl fonctionne
kubectl get nodes

# 2. Créer le fichier credentials GCP (format AWS S3)
cat > credentials-gcp << 'EOF'
[default]
aws_access_key_id = <TA_CLE_ACCESS>
aws_secret_access_key = <TON_SECRET>
EOF

# 3. Installer Velero avec le provider AWS (qui parle S3 à GCP)
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.2 \
    --bucket k8s_vagrant_velero \
    --secret-file ./credentials-gcp \
    --use-volume-snapshots=false \
    --backup-location-config region=us-east1,s3ForcePathStyle="true",s3Url=https://storage.googleapis.com

# 4. Vérifier
kubectl get pods -n velero
velero backup get
kubectl get backupstoragelocation -n velero
```

**Option B : GCP natif (voir section 7 Option B)**

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

### Session 3 : Commandes et options

#### Auto-complétion Velero CLI

```bash
# Bash
velero completion bash
echo 'source <(velero completion bash)' >> ~/.bashrc

# Zsh
velero completion zsh >> ~/.zshrc
```

#### Syntaxe `velero restore create`

Velero utilise un pattern Kubernetes-like : `restore` est la commande parent, `create` est l'action.

**Actions disponibles pour `velero restore`** :
```bash
velero restore create   # Créer un restore
velero restore get      # Lister les restores
velero restore describe # Détails
velero restore logs     # Logs
velero restore delete   # Supprimer
```

**Options principales de `velero restore create`** :

| Option | Usage |
|--------|-------|
| `--from-backup <nom>` | Restaurer depuis un backup (utilisé dans les sessions) |
| `--from-schedule <nom>` | Restaurer depuis le dernier backup d'un schedule |
| `--namespace-mappings ns1:ns2` | Mapper un namespace vers un autre |
| `--exclude-namespaces` | Exclure des namespaces |
| `--include-namespaces` | Inclure certains namespaces |
| `--wait` | Attendre la fin du restore |

**Exemple namespace mapping** :
```bash
velero restore create restore-renamed \
    --from-backup demo-backup \
    --namespace-mappings default:demo-restore
```

---

## Références

- [Velero Docs](https://velero.io/docs/main/)
- [Velero on GitHub](https://github.com/vmware-tanzu/velero)
- [MinIO Evaluation Install](https://velero.io/docs/main/contributions/minio/)
- [Disaster Recovery](https://velero.io/docs/main/disaster-case/)
