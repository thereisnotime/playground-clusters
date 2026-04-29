# RKE2 Playground Cluster — Runbook

## Prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| VirtualBox | 7.x | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | 2.4+ | https://developer.hashicorp.com/vagrant/install |
| Terraform | 1.5+ | https://developer.hashicorp.com/terraform/install |
| just | any | https://github.com/casey/just |
| kubectl | matches RKE2 Kubernetes version | https://kubernetes.io/docs/tasks/tools/ |

No external cluster provisioner needed — RKE2 is installed directly on nodes via SSH.

Pre-download the Vagrant box:

```bash
vagrant box add bento/debian-12
```

---

## Quick reference

```
just init      # download providers (first time only)
just up        # bring up cluster (~10–15 min, downloads RKE2 binary per node)
just down      # tear down cluster
just rebuild   # down + up
just creds     # re-fetch kubeconfig to .rke2-configs/
just nodes     # kubectl get nodes -o wide
just pods      # kubectl get pods -A
just health    # nodes + pods overview
just status    # RKE2 server systemctl status on CP
just ssh <ip>  # open SSH shell on any node
just plan      # terraform plan (preview changes)
```

---

## Spin up

```bash
cd rke2/

# First time: download providers
just init

# Bring up VMs and bootstrap the cluster (~10–15 min)
just up
```

> **Note:** `just up` downloads the RKE2 binary (~200 MB) on each node from `get.rke2.io`.
> Make sure your host has a working internet connection.

Terraform will:

1. Generate per-node Vagrantfiles into `.vagrant-nodes/<name>/` and run `vagrant up`
2. Wait for SSH on each node's static IP (`192.168.56.x:22`)
3. Install RKE2 on the first control plane and start `rke2-server`
4. Wait for the first CP to report a Ready node
5. Install and join any additional control planes (when `control_plane_count > 1`)
6. Fetch the node token from the first CP and install RKE2 agent on each worker
7. Fetch and write `kubeconfig` to `.rke2-configs/kubeconfig` (with `127.0.0.1` replaced by the CP static IP)

After `just up` the kubeconfig is already written — no need to run `just creds` on first boot.

---

## Access the cluster

```bash
# Use just wrappers (no export needed)
just nodes
just pods
just health

# Or export for direct use
export KUBECONFIG=.rke2-configs/kubeconfig
kubectl get nodes -o wide
```

---

## Dynamic scaling

```bash
# Add a third worker
terraform apply -var="worker_count=3" -auto-approve && just creds

# Scale to 3 control planes (HA)
terraform apply -var="control_plane_count=3" -auto-approve && just creds

# Adjust per-node resources
terraform apply -var="node_cpus=4" -var="node_memory=4096" -auto-approve
```

IP assignment:
- Control planes: `192.168.56.10`, `.11`, `.12`, …
- Workers: `192.168.56.20`, `.21`, `.22`, …

---

## Day-2 operations

### Check node and pod health

```bash
just health
```

### SSH into a node

```bash
just ssh 192.168.56.10   # control plane
just ssh 192.168.56.20   # worker-1
```

### Check RKE2 server logs

```bash
just ssh 192.168.56.10
sudo journalctl -u rke2-server -f
```

### Upgrade RKE2

1. Update `rke2_version` in `variables.tf`
2. `just up` — Terraform re-runs the install provisioner with the new version, which upgrades in-place

### Upgrade Kubernetes

RKE2 version encodes the Kubernetes version (`v<k8s-version>+rke2r<patch>`). Update `rke2_version` in `variables.tf` and run `just up`.

---

## Tear down

### Full destroy

```bash
just down
```

Destroys all VMs and removes `.vagrant-nodes/` directories.

### Manual VM cleanup (if Terraform state is lost)

```bash
for dir in .vagrant-nodes/*/; do
  vagrant destroy -f --cwd "$dir"
done

VBoxManage list vms | grep rke2
VBoxManage unregistervm "rke2-cp-1" --delete
VBoxManage unregistervm "rke2-worker-1" --delete
VBoxManage unregistervm "rke2-worker-2" --delete

rm -rf .vagrant-nodes/
```

### Clean up local configs

```bash
rm -rf .rke2-configs/
```

### Remove the Vagrant box

```bash
vagrant box remove bento/debian-12
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs | VirtualBox host-only adapter not created | Run `VBoxManage hostonlyif create` and retry |
| `curl get.rke2.io` slow or fails | No internet from VM | Check VirtualBox NAT adapter; check host connection |
| RKE2 server timeout | First boot + download takes >10 min | Increase `node_boot_timeout` in `variables.tf` |
| Workers stuck NotReady | CNI (Canal) still initialising | Wait 60–90 s after `just up` |
| `kubectl` connection refused | Kubeconfig still has `127.0.0.1` | Run `just creds` to re-fetch with correct CP IP |

---

## Network layout

| VM | IP | Role |
|----|----|------|
| cp-1 | 192.168.56.10 | control plane / cluster endpoint |
| worker-1 | 192.168.56.20 | worker |
| worker-2 | 192.168.56.21 | worker |

All VMs have two NICs: VirtualBox NAT (`10.0.2.15`) and host-only (`192.168.56.x`). RKE2 is configured to advertise and listen on the static host-only IPs. The kubeconfig is patched to use `192.168.56.10:6443` instead of the loopback address RKE2 writes by default.

## RKE2 specifics

| Item | Value |
|------|-------|
| Config dir | `/etc/rancher/rke2/` |
| Kubeconfig (on node) | `/etc/rancher/rke2/rke2.yaml` |
| Node token | `/var/lib/rancher/rke2/server/node-token` |
| kubectl (on node) | `/var/lib/rancher/rke2/bin/kubectl` |
| Agent join port | `9345` (TCP) |
| API port | `6443` (TCP) |
| Default CNI | Canal (Flannel + Calico network policy) |
| Default ingress | NGINX |
