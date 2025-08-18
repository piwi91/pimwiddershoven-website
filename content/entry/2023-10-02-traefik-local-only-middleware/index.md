---
date: "2023-10-02"
title: Traefik IP whitelist on Kubernetes to allow local-only clients
slug: traefik-ip-white-list-on-kubernetes-to-allow-local-only-clients
description: Limit exposure of web applications on Kubernetes using Traefik ingress controller with IP whitelist middleware configuration.
tags:
- kubernetes
- traefik
- traefik-middleware
- ingress-controller
summary: Limit exposure of web applications on Kubernetes using Traefik ingress controller with IP whitelist middleware configuration.
---

## Kubernetes-at-home

In my previous blog post I shared that I'm running Kubernetes at home. You could read that I use MetalLB to create load balancers on-demand using dedicated IP addresses. This setup is perfect to expose applications outside the Kubernetes cluster fairly easy. However, for applications exposing a web interface this isn't the best option we got. Another option to expose applications, in particular web interfaces, is using an ingress. An ingress is a configuration that exposes a service using an ingress controller outside the Kubernetes cluster.

## Traefik v3 ingress controller

In my Kubernetes cluster I use Traefik v3 as ingress controller. It is the default ingress controller installed when you run k3s, which is what I'm using at home. Traefik v3 is an ingress controller that is highly customizable using middlewares. These middlewares can be used in ingress configuration (using annotations) to change the behaviour of the ingress (e.g., rewriting paths) or add additional features (e.g., basic authentication).

## IP whitelist middleware

Since I have my ingress controller connected directly to internet, I want to control which applications are exposed outside my local network. For instance, Frigate, which is an open-source AI-driven network video recorder (NVR), should't be exposed to the world wide web. To achieve this, I used the IP whitelist middleware of Traefik to only allow clients that originate from my local network.

An example of the IP whitelist middleware configuration for Traefik v3.

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  namespace: default
  name: allow-local-only
spec:
  ipWhiteList:
    sourceRange:
      - 127.0.0.1/32
      - 10.0.0.0/24
```

To use the middleware an annotation has to be added to the ingress configuration.

```yaml
traefik.ingress.kubernetes.io/router.middlewares: default-allow-local-only@kubernetescrd
```

Note that the name of the middleware uses the format **<namespace>**-**<name>**.

### IP whitelist not working (forbidden)

My first attempt failed, I only got "forbidden" whatever I tried. After some research I found out that the IP address seen by Traefik was not the IP address of the client but from the Kubernetes cluster. After some thought and with the help of Google I found the issue in the traffic policy of the load balancer service. By default, the `externalTrafficPolicy` is set to `Cluster` which routes traffic to cluster-wide endpoints which obscures the IP address of the client. Setting this to `Local` preserves the client IP address but has some drawbacks in traffic spreading. Since I'm just running a single node this doesn't botter me, but keep this in mind when you run a production cluster with multiple nodes.

To change `externalTrafficPolicy` for Traefik in k3s you need to create a `HelmChartConfig` for Traefik in `/var/lib/rancher/k3s/server/manifests`. An example below which also includes an annotation for the load balancer IP address for MetalLB.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      annotations:
        metallb.universe.tf/loadBalancerIPs: xxx.xxx.xxx.xxx
      spec:
        externalTrafficPolicy: Local
```

## Some additional notes

The `apiVersion` used for Traefik v3 in k3s differs from teh `apiVersion` in the Traefik documentation.
