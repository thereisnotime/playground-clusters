# k0s Playground Cluster — Runbook

## Prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| VirtualBox | 7.x | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | 2.4+ | https://developer.hashicorp.com/vagrant/install |
| Terraform | 1.5+ | https://developer.hashicorp.com/terraform/install |
| just | any | https://github.com/casey/just |
| k0sctl | latest | https://github.com/k0sproject/k0sctl/releases |
| kubectl | matches k0s Kubernetes version | https://kubernetes.io/docs/tasks/tools/ |

Install k0sctl (Linux):

```bash
curl -sSLf https://github.com/k0sproject/k0sctl/releases/latest/download/k0sctl-linux-amd64 \
  -o /usr/local/bin/k0sctl && chmod +x /usr/local/bin/k0sctl
```

Pre-download the Vagrant box to avoid a slow first-run pull:

```bash
vagrant box add bento/debian-12
```

---

## Quick reference

```
just init      # download providers (first time only)
just up        # bring up cluster
just down      # tear down cluster
just rebuild   # down + up
just creds     # fetch kubeconfig to .k0s-configs/
just nodes     # kubectl get nodes -o wide
just pods      # kubectl get pods -A
just health    # nodes + pods overview
just plan      # terraform plan (preview changes)
```

---

## Spin up

```bash
cd k0s/

# First time: download providers
just init

# Bring up VMs and bootstrap the cluster (~5–10 min)
just up

# Fetch kubeconfig
just creds
```

Terraform will:

1. Generate per-node Vagrantfiles from `Vagrantfile.tpl` into `.vagrant-nodes/<name>/`
2. Run `vagrant up` for each VM (Debian 12, host-only NIC + NAT NIC)
3. Generate `k0sctl.yaml` with all node IPs and SSH config
4. Wait for SSH on each node's static IP (`192.168.56.x:22`)
5. Run `k0sctl apply` — installs k0s on every node and bootstraps the cluster

`just creds` runs `k0sctl kubeconfig` to write `.k0s-configs/kubeconfig`.

---

## Access the cluster

```bash
# Use just wrappers (no export needed after just creds)
just nodes
just pods
just health

# Or use kubectl directly
export KUBECONFIG=.k0s-configs/kubeconfig
kubectl get nodes -o wide
```

---

## Dynamic scaling

Node counts are controlled by Terraform variables. The default is 1 control plane + 2 workers.

```bash
# Add a third worker
terraform apply -var="worker_count=3" -auto-approve && just creds

# Scale control planes (HA requires an odd number: 3)
terraform apply -var="control_plane_count=3" -auto-approve && just creds

# Adjust per-node resources
terraform apply -var="node_cpus=4" -var="node_memory=4096" -auto-approve
```

IP assignment:
- Control planes: `192.168.56.10`, `.11`, `.12`, …
- Workers: `192.168.56.20`, `.21`, `.22`, …

---

## Day-2 operations

### Show node and pod status

```bash
just health
```

### Tail logs for a pod

```bash
just logs <namespace> <pod>
```

### Check k0s status on the control plane

```bash
just status
```

### SSH into a node

```bash
ssh -i ~/.vagrant.d/insecure_private_key -o StrictHostKeyChecking=no vagrant@192.168.56.10
```

### Upgrade k0s

1. Update `k0s_version` in `variables.tf`
2. `just up` — k0sctl re-applies with the new version and performs a rolling upgrade

### Upgrade Kubernetes

k0s version encodes the Kubernetes version (`v<k8s-version>+k0s.<patch>`). Update `k0s_version` in `variables.tf` to the target Kubernetes version and run `just up`.

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
  vagrant destroy -f --cwd "$dir"
done

# Remove lingering VirtualBox VMs if vagrant destroy fails
VBoxManage list vms | grep k0s
VBoxManage unregistervm "k0s-cp-1" --delete
VBoxManage unregistervm "k0s-worker-1" --delete
VBoxManage unregistervm "k0s-worker-2" --delete

# Remove node directories
rm -rf .vagrant-nodes/
```

### Clean up local configs

```bash
rm -rf .k0s-configs/
rm -f k0sctl.yaml
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
| `k0sctl apply` SSH timeout | Nodes still booting | Wait 30 s and retry; check `vagrant status` in `.vagrant-nodes/<name>/` |
| k0sctl "permission denied" | Wrong SSH key or key not at default path | Check `var.ssh_key_path`; ensure `config.ssh.insert_key = false` in Vagrantfile |
| Nodes stuck in NotReady | CNI not ready yet | Wait 60 s; k0s installs kube-router by default |
| VMs up but no IP on 192.168.56.x | Host-only network mismatch | Check VirtualBox Network settings |

---

## Network layout

| VM | IP | Role |
|----|----|------|
| cp-1 | 192.168.56.10 | control plane / cluster endpoint |
| worker-1 | 192.168.56.20 | worker |
| worker-2 | 192.168.56.21 | worker |

Additional nodes continue the sequence: CPs from `.10`, workers from `.20`.

All VMs have two NICs: VirtualBox NAT (`10.0.2.15`, used by Vagrant for initial SSH) and a host-only NIC (`192.168.56.x`, used by k0sctl and kubectl after boot). The host can reach all nodes directly.
