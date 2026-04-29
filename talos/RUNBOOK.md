# Talos Playground Cluster — Runbook

## Prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| VirtualBox | 7.x | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | 2.4+ | https://developer.hashicorp.com/vagrant/install |
| Terraform | 1.5+ | https://developer.hashicorp.com/terraform/install |
| just | any | https://github.com/casey/just |
| talosctl | v1.12.7 | `brew install siderolabs/tap/talosctl` |
| kubectl | matches `var.kubernetes_version` | https://kubernetes.io/docs/tasks/tools/ |

Pre-download the Vagrant box to avoid a slow first-run pull (~466 MB):

```bash
vagrant box add theorigamicorporation/talos-virtualbox --box-version 2.0.0
```

> Box `theorigamicorporation/talos-virtualbox 2.0.0` — Talos v1.12.7, VirtualBox amd64.  
> The version is controlled by `var.box_version` (default `2.0.0`).

---

## Quick reference

```
just init      # download providers (first time only)
just up        # bring up cluster
just down      # tear down cluster
just rebuild   # down + up
just creds     # write kubeconfig + talosconfig to .talos-configs/
just nodes     # kubectl get nodes -o wide
just pods      # kubectl get pods -A
just health    # talosctl health on control plane
just plan      # terraform plan (preview changes)
```

---

## Spin up

```bash
cd talos/

# First time: download providers
just init

# Bring up VMs and bootstrap the cluster (~10–15 min)
just up
```

Terraform will:

1. Generate per-node Vagrantfiles from `Vagrantfile.tpl` into `.vagrant-nodes/<name>/`
2. Run `vagrant up` (with `VAGRANT_EXPERIMENTAL=none_communicator`) for each VM in parallel
3. Generate cluster PKI via `hashicorp/tls` (ECDSA P256 CAs) and random bootstrap tokens
4. Wait for the Talos maintenance API on each node (via NAT port forwarding on `127.0.0.1`)
5. Push machine configs (including static IP on the host-only NIC) to each node
6. Bootstrap etcd on the first control plane (connects via static IP after reboot)
7. Retrieve kubeconfig

> If you run `vagrant` commands manually outside Terraform, prefix with the experimental flag:
> ```bash
> VAGRANT_EXPERIMENTAL=none_communicator vagrant up
> VAGRANT_EXPERIMENTAL=none_communicator vagrant status
> VAGRANT_EXPERIMENTAL=none_communicator vagrant destroy -f
> ```

---

## Access the cluster

```bash
# Write kubeconfig and talosconfig to .talos-configs/
just creds

# Use just wrappers (no export needed)
just nodes
just pods
just health

# Or export for direct kubectl/talosctl use
export KUBECONFIG=.talos-configs/kubeconfig
kubectl get nodes

talosctl --talosconfig .talos-configs/talosconfig \
    --endpoints 192.168.56.10 --nodes 192.168.56.10 \
    health
```

---

## Dynamic scaling

Node counts are controlled by Terraform variables. The default is 1 control plane + 2 workers.

```bash
# Add a third worker (no downtime to existing nodes)
terraform apply -var="worker_count=3" -auto-approve

# Scale control planes (e.g. for HA)
terraform apply -var="control_plane_count=3" -auto-approve

# Adjust vCPUs/memory per node (applies on next rebuild)
terraform apply -var="node_cpus=4" -var="node_memory=4096" -auto-approve
```

IP assignment:
- Control planes: `192.168.56.10`, `.11`, `.12`, …
- Workers: `192.168.56.20`, `.21`, `.22`, …

---

## Day-2 operations

### Check node health

```bash
just health
```

### Show all pods

```bash
just pods
```

### Tail logs for a pod

```bash
just logs <namespace> <pod>
```

### View kernel logs / services on the control plane

```bash
just dmesg
just services
```

### Get raw node logs via talosctl

```bash
talosctl --talosconfig .talos-configs/talosconfig \
    --endpoints 192.168.56.10 --nodes 192.168.56.10 \
    logs kubelet
```

### Upgrade Talos on a node

1. Update `box_version` and `talos_version` in `variables.tf` to the new release
2. `just up` pushes the updated machine config
3. Upgrade each node in-place:

```bash
talosctl --talosconfig .talos-configs/talosconfig \
    --endpoints 192.168.56.10 --nodes 192.168.56.10 \
    upgrade --image ghcr.io/siderolabs/installer:v1.12.7
```

### Upgrade Kubernetes

1. Update `kubernetes_version` in `variables.tf`
2. `just up` pushes the new machine config
3. Trigger the upgrade:

```bash
talosctl --talosconfig .talos-configs/talosconfig \
    --endpoints 192.168.56.10 --nodes 192.168.56.10 \
    upgrade-k8s --to v1.33.1
```

---

## Tear down

### Full destroy

```bash
just down
```

This destroys all VMs (via `vagrant destroy -f` in each `.vagrant-nodes/<name>/`) and removes the node directories.

### Manual VM cleanup (if Terraform state is lost)

```bash
# Destroy each node's Vagrant environment
for dir in .vagrant-nodes/*/; do
  VAGRANT_EXPERIMENTAL=none_communicator vagrant destroy -f --cwd "$dir"
done

# Remove lingering VirtualBox VMs if vagrant destroy fails
VBoxManage list vms | grep talos
VBoxManage unregistervm "talos-cp-1" --delete
VBoxManage unregistervm "talos-worker-1" --delete
VBoxManage unregistervm "talos-worker-2" --delete

# Remove node directories
rm -rf .vagrant-nodes/
```

### Clean up local configs

```bash
rm -rf .talos-configs/
```

### Remove the Vagrant box

```bash
vagrant box remove theorigamicorporation/talos-virtualbox --box-version 2.0.0
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs on boot | VirtualBox host-only adapter not created | Run `VBoxManage hostonlyif create` and retry |
| `talosctl` times out after apply | Nodes still booting | Wait 60–90 s and retry |
| etcd bootstrap fails | Control plane config not applied cleanly | `talosctl --nodes 192.168.56.10 logs etcd` |
| `terraform apply` errors on talos resources | Talos API not reachable | Check VMs: `ls .vagrant-nodes/` then `vagrant status` in each dir |
| VMs up but no IP on `192.168.56.x` | Host-only network mismatch | Check VirtualBox Network settings; adjust IP range if needed |
| CoreDNS pods not Ready | Upstream DNS unreachable from pod namespace | CoreDNS forwards to `10.0.2.3` (VirtualBox NAT DNS) — verify that adapter is present |

---

## Network layout

| VM | IP | Talos API port (NAT) | Role |
|----|----|----------------------|------|
| cp-1 | 192.168.56.10 | 50001 | control plane / cluster endpoint |
| worker-1 | 192.168.56.20 | 50002 | worker |
| worker-2 | 192.168.56.21 | 50003 | worker |

Additional nodes continue the sequence: CPs from `.10`, workers from `.20`; ports from `50001` upward.

All VMs share a VirtualBox host-only network (`192.168.56.0/24`). The host machine can reach all nodes directly. VMs also have a VirtualBox NAT NIC (`10.0.2.15`) — Terraform uses NAT port forwarding during initial config apply; all subsequent traffic uses static host-only IPs.
