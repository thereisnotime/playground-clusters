# playground-clusters

Local Kubernetes playground for spinning up and tearing down clusters of different distributions. Each cluster runs on VirtualBox VMs provisioned by Vagrant and configured by Terraform. Vagrant boxes are built with Packer and published to HCP Vagrant Registry.

## Stack

| Layer | Tool |
|-------|------|
| Hypervisor | VirtualBox |
| VM lifecycle | Vagrant |
| Infrastructure | Terraform |
| Box builds | Packer |
| Task runner | just |

## Clusters

| Directory | Distro | Box | Provisioner |
|-----------|--------|-----|-------------|
| [`talos/`](talos/) | [Talos Linux](https://www.talos.dev) | `theorigamicorporation/talos-virtualbox` | Talos Terraform provider |
| [`k0s/`](k0s/) | [k0s](https://k0sproject.io) | `bento/debian-12` | k0sctl |
| [`rke2/`](rke2/) | [RKE2](https://docs.rke2.io) | `bento/debian-12` | SSH shell scripts |

All clusters follow the same layout and expose the same `just` commands.

## Network layout

Every cluster uses the same IP scheme on a VirtualBox host-only network (`192.168.56.0/24`):

| Role | IPs |
|------|-----|
| Control planes | `192.168.56.10`, `.11`, `.12`, … |
| Workers | `192.168.56.20`, `.21`, `.22`, … |

Node counts, vCPUs, and memory are all Terraform variables — scale up or down without recreating the whole cluster.

## Quick start

Pick a cluster directory and run:

```bash
just init    # download Terraform providers (first time only)
just up      # spin up VMs and bootstrap the cluster
just creds   # write kubeconfig (and talosconfig for Talos)
just nodes   # kubectl get nodes -o wide
just pods    # kubectl get pods -A
just down    # tear everything down
```

### Scaling

```bash
# Add a worker
terraform apply -var="worker_count=3" -auto-approve

# Different CPU/RAM per role
terraform apply \
  -var="control_plane_cpus=4" -var="control_plane_memory=8192" \
  -var="worker_cpus=2"        -var="worker_memory=4096" \
  -auto-approve
```

## Prerequisites

| Tool | Install |
|------|---------|
| VirtualBox 7.x | https://www.virtualbox.org/wiki/Downloads |
| asdf | https://asdf-vm.com/guide/getting-started.html |
| Vagrant | `asdf plugin add vagrant` |
| Terraform | `asdf plugin add terraform` |
| just | `asdf plugin add just` |
| kubectl | `asdf plugin add kubectl` |
| talosctl *(Talos only)* | `asdf plugin add talosctl` |
| k0sctl *(k0s only)* | `asdf plugin add k0sctl` |

Versions are pinned in each cluster's `.tool-versions`. Run `asdf install` inside a cluster directory to install them.

## Box builds

The Talos box (`theorigamicorporation/talos-virtualbox`) is built with Packer from a raw Talos disk image and published to HCP Vagrant Registry. See [`vagrant-talos`](https://github.com/theorigamicorporation/vagrant-talos) for the build repo.

Standard Debian boxes (`bento/debian-12`) are pulled directly from Vagrant Cloud.

## Runbooks

Each cluster has a `RUNBOOK.md` with full details on day-2 operations, upgrades, manual cleanup, and troubleshooting.
