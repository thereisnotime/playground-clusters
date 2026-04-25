# Talos Playground Cluster — Runbook

## Prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| VirtualBox | 7.x | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | 2.4+ | https://developer.hashicorp.com/vagrant/install |
| Terraform | 1.5+ | https://developer.hashicorp.com/terraform/install |
| talosctl | v1.12.7 | `brew install siderolabs/tap/talosctl` |
| kubectl | matches `var.kubernetes_version` | https://kubernetes.io/docs/tasks/tools/ |

Pre-download the Vagrant box to avoid a slow first-run pull (466 MB):

```bash
vagrant box add theorigamicorporation/talos-virtualbox --box-version 1.0.0
```

> Box is `theorigamicorporation/talos-virtualbox 1.0.0` — Talos v1.12.7, VirtualBox amd64.

---

## Spin up

```bash
cd talos/

# Download providers
terraform init

# Preview what will be created
terraform plan

# Bring up VMs and configure the cluster (~10-15 min)
terraform apply
```

Terraform will:
1. Run `vagrant up` (with `VAGRANT_EXPERIMENTAL=none_communicator`) for all three VMs
2. Wait for the Talos maintenance API to become reachable on each node via NAT port forwarding
3. Generate Talos PKI and secrets
4. Push machine configs (including static IP assignment for the host-only NIC) to each node via the forwarded ports
5. Bootstrap etcd on the control plane (connects via static IP after first reboot)
6. Retrieve kubeconfig

> **Note:** If you want to run `vagrant` commands manually outside of Terraform, prefix them with the experimental flag:
> ```bash
> VAGRANT_EXPERIMENTAL=none_communicator vagrant up
> VAGRANT_EXPERIMENTAL=none_communicator vagrant status
> VAGRANT_EXPERIMENTAL=none_communicator vagrant destroy -f
> ```

---

## Access the cluster

```bash
# Export talosconfig
terraform output -raw talosconfig > ~/.talos/config
# or merge into existing:
terraform output -raw talosconfig | talosctl config merge -

# Export kubeconfig
terraform output -raw kubeconfig > ~/.kube/talos-playground
export KUBECONFIG=~/.kube/talos-playground

# Verify
kubectl get nodes
talosctl --nodes 192.168.56.10 health
```

---

## Day-2 operations

### Check node health

```bash
talosctl --nodes 192.168.56.10,192.168.56.11,192.168.56.12 health
```

### Tail logs from a node

```bash
talosctl --nodes 192.168.56.10 logs kubelet
```

### Get a shell / dmesg

```bash
talosctl --nodes 192.168.56.10 dmesg
talosctl --nodes 192.168.56.10 services
```

### Upgrade Talos on a node

1. Update `talos_version` in `variables.tf`
2. Update `TALOS_VERSION` in `Vagrantfile`
3. Run `terraform apply` — config is re-pushed; then upgrade each node:

```bash
talosctl --nodes 192.168.56.10 upgrade --image ghcr.io/siderolabs/installer:v1.12.7
```

### Upgrade Kubernetes

1. Update `kubernetes_version` in `variables.tf`
2. `terraform apply` pushes the new machine config
3. Trigger the upgrade:

```bash
talosctl --nodes 192.168.56.10 upgrade-k8s --to v1.32.3
```

---

## Tear down

### Full destroy (VMs + Terraform state)

```bash
terraform destroy
```

This removes all three VMs and deletes the Talos secrets from state.

### Manual VM cleanup (if Terraform state is lost)

```bash
# From the talos/ directory
VAGRANT_EXPERIMENTAL=none_communicator vagrant destroy -f

# Remove lingering VirtualBox VMs if vagrant destroy fails
VBoxManage list vms | grep talos
VBoxManage unregistervm "talos-cp-1" --delete
VBoxManage unregistervm "talos-worker-1" --delete
VBoxManage unregistervm "talos-worker-2" --delete
```

### Clean up local configs

```bash
rm -f ~/.talos/config
rm -f ~/.kube/talos-playground

# Remove Vagrant machine state
rm -rf .vagrant/
```

### Remove the Vagrant box

```bash
vagrant box remove theorigamicorporation/talos-virtualbox --box-version 1.0.0
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs on boot | VirtualBox host-only adapter not created | Run `VBoxManage hostonlyif create` and retry |
| `talosctl` times out after apply | Nodes still booting | Wait 60-90 s and retry |
| etcd bootstrap fails | Control plane config not applied cleanly | Check `talosctl --nodes 192.168.56.10 logs etcd` |
| `terraform apply` errors on talos resources | Talos API not reachable | Ensure VMs are up: `vagrant status` |
| VMs created but no IP on `192.168.56.x` | Host-only network mismatch | Check VirtualBox Network settings; adjust IP range if needed |

---

## Network layout

| VM | IP | Role |
|----|----|------|
| cp-1 | 192.168.56.10 | control plane / cluster endpoint |
| worker-1 | 192.168.56.11 | worker |
| worker-2 | 192.168.56.12 | worker |

All VMs share a VirtualBox host-only network (`192.168.56.0/24`). The host machine can reach all nodes directly.
