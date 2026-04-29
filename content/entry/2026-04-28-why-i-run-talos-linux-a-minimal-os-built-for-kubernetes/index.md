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
