# kubeadm Playground Cluster — Runbook

## Quick reference

```
just init      # download providers (first time only)
just up        # bring up cluster (~15–20 min, downloads packages on each node)
just down      # tear down cluster
just rebuild   # down + up
just creds     # re-fetch kubeconfig to .kubeadm-configs/
just nodes     # kubectl get nodes -o wide
just pods      # kubectl get pods -A
just health    # nodes + pods overview
just status    # kubelet status on CP
just ssh <ip>  # open SSH shell on any node
just plan      # terraform plan (preview changes)
```

---

## Spin up

```bash
cd kubeadm/
just init
just up
```

Terraform will:

1. Generate per-node Vagrantfiles into `.vagrant-nodes/<name>/` and run `vagrant up`
2. Wait for SSH on each node
3. On every node (in parallel): disable swap, configure kernel modules and sysctl, install containerd (Docker repo) with SystemdCgroup, install kubeadm/kubelet/kubectl, pin kubelet node IP
4. Run `kubeadm init` on the first control plane and install Flannel CNI
5. Wait for the first CP to report a Ready node
6. Join any additional control planes (when `control_plane_count > 1`)
7. Join workers via `kubeadm join`
8. Fetch and write `kubeconfig` to `.kubeadm-configs/kubeconfig`

> **Note:** Node prep downloads packages from Docker and Kubernetes apt repos (~200 MB per node). Spin-up takes 15–20 min on a fresh box.

---

## Access the cluster

```bash
just nodes
just pods

export KUBECONFIG=.kubeadm-configs/kubeconfig
kubectl get nodes -o wide
```

---

## Scaling

```bash
# Add a third worker
terraform apply -var="worker_count=3" -auto-approve

# Scale to 3 control planes (HA)
terraform apply -var="control_plane_count=3" -auto-approve

# Adjust resources per role
terraform apply \
  -var="control_plane_cpus=4" -var="control_plane_memory=8192" \
  -var="worker_cpus=2"        -var="worker_memory=4096" \
  -auto-approve
```

IP assignment:
- Control planes: `192.168.56.10`, `.11`, `.12`, …
- Workers: `192.168.56.20`, `.21`, `.22`, …

---

## Day-2 operations

### SSH into a node

```bash
just ssh 192.168.56.10   # control plane
just ssh 192.168.56.20   # worker-1
```

### Check kubelet logs

```bash
just ssh 192.168.56.10
sudo journalctl -u kubelet -f
```

### Upgrade Kubernetes

1. Update `kubernetes_version` in `variables.tf`
2. `just rebuild` — kubeadm upgrades require node drain + `kubeadm upgrade`; a full rebuild is simpler for a playground

### Reset a node manually

```bash
just reset-node 192.168.56.20
```

---

## Tear down

```bash
just down
```

### Manual cleanup (if Terraform state is lost)

```bash
for dir in .vagrant-nodes/*/; do
  vagrant destroy -f --cwd "$dir"
done

VBoxManage list vms | grep kubeadm
VBoxManage unregistervm "kubeadm-cp-1" --delete
VBoxManage unregistervm "kubeadm-worker-1" --delete
VBoxManage unregistervm "kubeadm-worker-2" --delete

rm -rf .vagrant-nodes/ .kubeadm-configs/
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs | VirtualBox host-only adapter not created | Run `VBoxManage hostonlyif create` and retry |
| apt install fails | No internet from VM | Check VirtualBox NAT adapter |
| `kubeadm init` times out | etcd or apiserver OOM | Increase `control_plane_memory` (default 4096 MB) |
| Nodes stuck NotReady | Flannel CNI still initialising | Wait 60–90 s; run `just pods` to watch |
| Workers can't join | Bootstrap token expired (24 h TTL) | Terraform will generate a fresh token on each apply |
| Wrong node IP in `kubectl get nodes` | KUBELET_EXTRA_ARGS not applied | Check `/etc/default/kubelet` on the node |

---

## Network layout

| VM | IP | Role |
|----|----|------|
| cp-1 | 192.168.56.10 | control plane / cluster endpoint |
| worker-1 | 192.168.56.20 | worker |
| worker-2 | 192.168.56.21 | worker |

All VMs have two NICs: VirtualBox NAT (`10.0.2.15`) and host-only (`192.168.56.x`). kubelet is configured with `--node-ip` pointing to the static host-only address.

## kubeadm specifics

| Item | Value |
|------|-------|
| Container runtime | containerd (Docker repo) |
| Kubeconfig (on node) | `/etc/kubernetes/admin.conf` |
| Bootstrap token TTL | 24 hours (auto-renewed by Terraform on apply) |
| API port | `6443` (TCP) |
| Default CNI | Flannel (`10.244.0.0/16`) |
| Node reset | `kubeadm reset -f` |
