# Problèmes Snapshot Restore avec Kubernetes + Calico

## Observations

### Symptômes constatés
- Après un `vagrant halt` + restore snapshot:
  - ✅ Tous les pods Kubernetes sont "Running"
  - ✅ Tous les pods Calico sont "Running"
  - ❌ La création de nouveaux pods reste bloquée en "ContainerCreating"
  - ❌ Erreur réseau: `plugin type="calico" failed (add): error getting ClusterInformation: connection is unauthorized: Unauthorized`

### Tests effectués
1. **Réseau VM → VM:**
   - ✅ Les VMs peuvent se pinguer entre elles (10.0.10.x)
   - ✅ Les interfaces eth0, eth1, eth2 existent correctement

2. **Calico:**
   - ❌ Les pods Calico sont "Running" mais pas "Ready"
   - ❌ BIRD (BGP) ne s'établit pas entre les nodes
   - ❌ Logs: "BGP not established with 10.0.10.21,10.0.10.22"

3. **Réinstallation Calico:**
   - ❌ Supprimer + réinstaller ne résout pas le problème
   - ❌ Supprimer les données Calico (/var/lib/calico) ne résout pas

4. **Kubelet:**
   - ❌ Redémarrer kubelet ne résout pas

### Conclusions
- Le problème est **systématique** après chaque halt/restore
- Les données semblent "gelées" dans un état incohérent
- Ce n'est pas un problème de réseau (les VMs communiquent)
- Ce n'est pas un problème de Calico seul (réinstaller ne change rien)
- À tester: restore SANS Calico (le problème est-il présent?)

---

## Solutions envisageables

### 1. Utiliser etcd sur le host (Option A)

**Concept:** Monter le répertoire etcd depuis le host via VirtualBox Shared Folder, ainsi les données persistent et ne sont pas affectées par le snapshot.

**Configuration Vagrantfile:**
```ruby
# Sur le control-plane
config.vm.synced_folder "./etcd-data", "/var/lib/etcd", 
  type: "virtualbox",
  automount: true

# Après, réinstaller Kubernetes avec:
kubeadm init --etcd-dir=/var/lib/etcd
```

**Avantages:**
- etcd persiste entre les snapshots
- Le cluster peut être restauré sans perte de données

**Inconvénients:**
- Complexe à mettre en place sur un cluster existant
- Performance potentiellement réduite
- Perds l'intérêt du "stateless" de etcd

---

### 2. Utiliser suspend/resume au lieu de halt/up (Option B)

**Concept:** Au lieu d'arrêter complètement les VMs, les mettre en veille.

```bash
# Au lieu de:
vagrant halt
vagrant up

# Utiliser:
vagrant suspend
vagrant resume
```

**Avantages:**
- Les VMs ne sont pas vraiment arrêtées
- etcd reste cohérent
- Simple à mettre en place

**Inconvénients:**
- Consomme de la mémoire RAM en veille
- Pas équivalent à un "vrai" arrêt

---

### 3. Ne pas utiliser de snapshots avec Calico (Option C)

**Concept:** Accepter que les snapshots ne fonctionnent pas avec Calico et utiliser une autre méthode de backup.

**Méthodes alternatives:**
- Export des manifestes: `kubectl get all --all-namespaces -o yaml > backup.yaml`
- Backup de la config Kubernetes
- Ne pas arrêter les VMs (les laisser tourner)

---

## Recommandations

### Pour un environnement de développement local

L'**Option B** (suspend/resume) semble la plus adaptée:
- Simple à mettre en place
- Résout le problème de cohérence
- Pas de modification de l'architecture

### Pour un environnement de production

L'**Option A** (etcd sur host) serait plus robuste, mais:
- Requiert une réinstallation complète du cluster
- Nécessite une configuration kubeadm modifiée
- Complexe à maintenir

---

## Questions ouvertes

1. Pourquoi le snapshot restore cause-t-il systématiquement ce problème?
2. Est-ce un problème connu avec Calico + VirtualBox?
3. Y a-t-il une configuration Calico qui survive aux restores?

---

## À tester

- [ ] Option A: etcd sur host
- [ ] Option B: suspend/resume
- [ ] Restore SANS Calico (le problème est-il spécifique à Calico?)
- [ ] Documenter les résultats
