# k3s Playground Cluster — Runbook

## Quick reference

```
just init      # download providers (first time only)
just up        # bring up cluster (~5–10 min)
just down      # tear down cluster
just rebuild   # down + up
just creds     # re-fetch kubeconfig to .k3s-configs/
just nodes     # kubectl get nodes -o wide
just pods      # kubectl get pods -A
just health    # nodes + pods overview
just status    # k3s service status on CP
just ssh <ip>  # open SSH shell on any node
just plan      # terraform plan (preview changes)
```

---

## Spin up

```bash
cd k3s/
just init
just up
```

Terraform will:

1. Generate per-node Vagrantfiles into `.vagrant-nodes/<name>/` and run `vagrant up`
2. Wait for SSH on each node's static IP (`192.168.56.x:22`)
3. Write `/etc/rancher/k3s/config.yaml` and install k3s server on the first control plane
4. Wait for the first CP to report a Ready node
5. Fetch the node token and join any additional control planes (when `control_plane_count > 1`)
6. Fetch the node token and install k3s agent on each worker
7. Fetch and write `kubeconfig` to `.k3s-configs/kubeconfig`

---

## Access the cluster

```bash
just nodes
just pods

export KUBECONFIG=.k3s-configs/kubeconfig
kubectl get nodes -o wide
```

---

## Scaling

```bash
# Add a third worker
terraform apply -var="worker_count=3" -auto-approve

# Scale to 3 control planes (HA via embedded etcd)
terraform apply -var="control_plane_count=3" -auto-approve

# Adjust resources per role
terraform apply \
  -var="control_plane_cpus=4" -var="control_plane_memory=4096" \
  -var="worker_cpus=2"        -var="worker_memory=2048" \
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

### Check k3s logs

```bash
just ssh 192.168.56.10
sudo journalctl -u k3s -f
```

### Upgrade k3s

1. Update `k3s_version` in `variables.tf`
2. `just up` — Terraform re-runs the install provisioner which upgrades in-place

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

VBoxManage list vms | grep k3s
VBoxManage unregistervm "k3s-cp-1" --delete
VBoxManage unregistervm "k3s-worker-1" --delete
VBoxManage unregistervm "k3s-worker-2" --delete

rm -rf .vagrant-nodes/ .k3s-configs/
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs | VirtualBox host-only adapter not created | Run `VBoxManage hostonlyif create` and retry |
| k3s install hangs | Slow download from `get.k3s.io` | Wait; increase `node_boot_timeout` if needed |
| Nodes stuck NotReady | Flannel (`local-path`) still initialising | Wait 30–60 s after `just up` |
| Workers can't reach server | Token mismatch or wrong server IP | Run `just rebuild` |

---

## Network layout

| VM | IP | Role |
|----|----|------|
| cp-1 | 192.168.56.10 | control plane / cluster endpoint |
| worker-1 | 192.168.56.20 | worker |
| worker-2 | 192.168.56.21 | worker |

All VMs have two NICs: VirtualBox NAT (`10.0.2.15`) and host-only (`192.168.56.x`). k3s is configured to advertise and listen on the static host-only IPs.

## k3s specifics

| Item | Value |
|------|-------|
| Config dir | `/etc/rancher/k3s/` |
| Kubeconfig (on node) | `/etc/rancher/k3s/k3s.yaml` |
| Node token | `/var/lib/rancher/k3s/server/node-token` |
| Server join port | `6443` (TCP) |
| Peer port (HA etcd) | `2379`, `2380` (TCP) |
| Default CNI | Flannel |
| Default storage | local-path provisioner |
| Server uninstall | `k3s-uninstall.sh` |
| Agent uninstall | `k3s-agent-uninstall.sh` |
