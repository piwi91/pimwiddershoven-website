---
date: "2026-04-28"
title: "Why I Run Talos Linux: A Minimal OS Built for Kubernetes"
slug: "why-i-run-talos-linux-a-minimal-os-built-for-kubernetes"
description: "Talos Linux is a minimal, immutable, API-driven operating system built specifically to run Kubernetes. This post walks through why it works in production, how I run it on a 3-node homelab, and the configs you need to copy."
tags: ["talos", "talos-linux", "kubernetes", "kubernetes-os", "homelab", "infrastructure", "platform-engineering", "system-extensions"]
summary: "Talos is a Kubernetes-only OS — bare minimum to run K8s, with system extensions for everything from DRBD storage to GPU drivers. I walk through the 3-node cluster I run at home, the configs you can copy to follow along, and what surprised me — including the 32 GB lesson and the templating gap I'm still trying to solve."
---

The first time I tried to SSH into a Talos node, nothing listened. No port 22, no shell prompt, nothing to log into. My first instinct was that something had broken. Then I remembered: that's the point.

Talos Linux doesn't ship with SSH. It doesn't ship with a shell either. There is no `apt`, no `yum`, no systemd unit zoo to reason about, no `/etc` to edit, no package upgrades to babysit. The only way to talk to a node is through an API. And once you sit with that for a while, it stops feeling weird and starts feeling like the way an OS that runs Kubernetes should have worked all along.

This post is about why I picked Talos for my cluster, what makes it different from "yet another Linux distro", and how to get a 3-node cluster running yourself. I've baked in the configs you'd actually need, so you can copy them and adjust the IPs.

## The OS choice is not a default

Most write-ups about home Kubernetes clusters skip the OS entirely. You see "I installed k3s on Ubuntu" and the post moves on. That works, but it leaves you fighting the OS forever after.

If you pick a general-purpose distro, you inherit everything that comes with it. Package drift between nodes. Manual upgrades that you'll either automate yourself or forget for six months. A shell that invites you to "just" make a quick change on one node, which then doesn't match the others. Security patching that's your problem. Unit files, sysctls, kernel modules — all configured in slightly different ways on each box because you fixed something at 11pm and forgot to write it down.

The OS is the thing you fight every day if you pick wrong. Picking it should be a deliberate decision, not whatever was on the first guide you found.

I want to be clear about one thing up front: Talos is not a homelab toy. It's a production-grade operating system that real companies run real workloads on. The fact that it scales down beautifully to three mini-PCs in my office is a side effect of how it's designed, not its primary purpose. The homelab is just where I happen to run it.

## Talos is a Kubernetes operating system

This is the part that flips your worldview. Talos isn't a general-purpose Linux distribution that happens to be good at Kubernetes. It's a Kubernetes operating system. The entire OS is the bare minimum needed to run Kubernetes, and nothing else.

Concretely, here's what you don't get:

* No shell. No `bash`, no `sh`, no `busybox` you can drop into.
* No SSH daemon. Nothing on port 22.
* No package manager. You can't `apt install` anything.
* No systemd, no init.d scripts, no cron, no journald the way you're used to it.
* No `/etc` you edit by hand. The filesystem is read-only.

Here's what you do get:

* A Linux kernel.
* `containerd` and `kubelet`, configured and supervised.
* Two services that *are* the OS interface: `machined` (the supervisor) and `apid` (the gRPC API).
* A single declarative machine configuration, applied through the API.

That last one is the point. You don't configure a Talos node by SSH-ing in and changing things. You configure it by sending it a YAML document that describes the desired state, and `machined` makes it so. Hostname, network interfaces, disk layout, kubelet flags, kernel parameters, registry mirrors, time servers — all of it lives in one machine config that you apply with `talosctl apply-config`.

The whole thing is immutable. The root filesystem is read-only at runtime. There are A and B partitions, and an upgrade is literally "boot from the other partition with a new image". If the upgrade goes wrong, the next boot rolls back. There's no in-place package upgrade that can leave you halfway between versions.

This is also why Talos works equally well in production and in a homelab. The model is the same on both ends. A managed Kubernetes vendor running thousands of clusters and a person running three nodes at home are interacting with the OS through the same gRPC API, applying the same machine config schema, doing the same image-swap upgrades. Same OS, same primitives, same guarantees. The blast radius of a 2am mistake is also dramatically smaller, because there's far less surface area to mess up.

The first week of using Talos is mostly unlearning habits. You won't `tail -f` a log on a node. You'll `talosctl logs`. You won't edit a config file. You'll patch the machine config and re-apply. You won't drop into a container's host. You'll ask the API. It feels strict at first, then quiet, then obvious.

## System extensions: minimal core, opt-in capabilities

The other half of what makes Talos a gamechanger is how it handles "everything else". Because the core is intentionally tiny, anything beyond "run Kubernetes" is added through **system extensions** that get baked into the boot image at build time.

Think of extensions as the answer to the question: "but I need X". Some of the ones I or people I know reach for:

* **`iscsi-tools`** and **`util-linux-tools`** — needed for iSCSI-based storage like Piraeus / LINSTOR.
* **`drbd`** — kernel module for replicated block storage with LINSTOR.
* **NVIDIA / Intel GPU drivers** — for GPU workloads, transcoding, or local ML inference.
* **`intel-ucode` / `amd-ucode`** — CPU microcode updates baked into the image.
* **`qemu-guest-agent`** — if you're running Talos as a VM on Proxmox or similar.
* **`zfs`** — for ZFS-backed storage.
* **`tailscale`** — for cross-site networking.

You don't `apt install` any of this. You don't run a script on the node. You declare which extensions you want, and Talos's [Image Factory](https://factory.talos.systems) builds a custom boot image that includes them. The extensions become part of the immutable image, just like the kernel.

That's it. That's the whole model. Tiny core, declarative list of extensions, custom image. Once you internalise it, "how do I install X on the node?" stops being a question. The answer is always: add the extension to the schematic, rebuild the image, upgrade the node to the new image. Same flow every time, no matter what X is.

Here's an example schematic — the YAML that tells the Image Factory which extensions to bake in:

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
      - siderolabs/intel-ucode
      - siderolabs/i915-ucode
      - siderolabs/qemu-guest-agent
```

You POST this to the Image Factory and get back a schematic ID — a long hex string that represents this exact extension set. That ID then goes into your image URL.

```bash
curl -X POST --data-binary @schematic.yaml https://factory.talos.systems/schematics
# {"id":"376567988e75d96c6f9f96e6c07f83b80beae62e5c1b6c4b3b9e8b22ad9f1234"}
```

Save that ID — you'll need it twice. Once to download the boot image, and once inside your machine config to tell the installer which image to use for upgrades.

## My setup

Three mini-PCs sit on a shelf next to my desk. Each one has a 6-core CPU, 500 GB NVMe SSD, and a single 1 Gb NIC. They're identical, which is the whole point — three interchangeable nodes that all run the control plane and also schedule workloads. There's no "special" node. If one dies, the cluster keeps running.

This is *my* environment. None of it is a Talos requirement. People run Talos on Raspberry Pis, on bare metal in datacenters, on cloud VMs, on Proxmox. The model doesn't care.

There is one hardware lesson I want to save you from learning the hard way: **don't start with 16 GB of RAM**. The mini-PCs I bought shipped with 16 GB each, and that felt generous on day one when the cluster was just nodes and a CNI. Then I added cert-manager. Then ingress. Then Cilium with Hubble. Then Keycloak for SSO. Then Forgejo for Git. Then observability — Prometheus, Loki, Grafana. By the time the platform layer was actually doing something useful, I was right up against the memory ceiling and watching the kubelet evict things during peak.

I upgraded all three to 32 GB and the problem went away. If you're sizing nodes today, save yourself the second purchase and go to 32 GB or more from day one. Memory is the constraint that bites first in a homelab Kubernetes cluster, every time.

## Build a custom Talos image

Time for the practical part. The first thing you need is a boot image with your extensions baked in.

Save the schematic from earlier as `schematic.yaml`, then ask the Image Factory for a schematic ID:

```bash
curl -X POST --data-binary @schematic.yaml \
  https://factory.talos.systems/schematics
```

You'll get back JSON with an `id` field. Pretend the ID is `abc123` for the rest of this post — substitute your real one.

Now you have two ways to get Talos onto your hardware:

* **ISO**, for one-off installs or PXE-less environments. Burn it to a USB stick, boot the node from it, and it'll run Talos in maintenance mode (no config applied yet). This is what I use at home.
* **Installer image**, used for upgrades after the initial install. Talos pulls this image when you run `talosctl upgrade`.

The URLs follow a simple pattern. For the ISO:

```
https://factory.talos.systems/image/abc123/v1.9.0/metal-amd64.iso
```

For the installer image (referenced inside the machine config):

```
factory.talos.systems/installer/abc123:v1.9.0
```

Download the ISO, write it to a USB stick with `dd` or your tool of choice, and boot all three nodes from it. They'll come up in maintenance mode with a temporary IP from DHCP, listening for a machine config on port 50000. That's all they do until you tell them more.
