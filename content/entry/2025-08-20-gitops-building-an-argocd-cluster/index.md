---
date: "2025-08-20"
title: "Building a Self-Managing ArgoCD Cluster"
slug: "building-self-managing-argocd-cluster"
description: "Learn how to implement a self-managing ArgoCD cluster that maintains itself through GitOps principles, eliminating manual intervention while ensuring consistent deployments."
tags: ["ArgoCD", "GitOps", "Kubernetes", "DevOps", "Automation", "Infrastructure-as-Code"]
summary: "Implementation guide for creating an ArgoCD cluster that manages its own configuration and updates through GitOps, including repository structure, app-of-apps pattern, and self-healing configuration."
---

GitOps solutions can manage applications and entire Kubernetes clusters through declarative configuration stored in Git repositories. ArgoCD, as a GitOps operator, can manage its own infrastructure and updates automatically, eliminating the need for manual cluster maintenance while ensuring consistent deployments.

This blog post demonstrates how to build an ArgoCD cluster that manages itself and all deployed applications through GitOps principles. Once implemented, infrastructure changes flow entirely through Git commits, removing the need for direct Kubernetes interaction while maintaining complete control over your deployment pipeline.

## Understanding GitOps

GitOps is an operational framework where Git repositories serve as the single source of truth for declarative infrastructure and application configuration. Benefits of GitOps are:
* **Version Control for Infrastructure**: All infrastructure changes are tracked through Git which gives you the ability to track, review and audit changes using standard Git workflows.
* **Declarative Configuration**: The state of your infrastructure is described in declarative code, making infrastructure predictable and easier to understand.
* **Automated Synchronization**: Controllers continuously monitor Git repositories and automatically apply changes to maintain desired state without manual intervention.
* **Enhanced Security**: By using Git workflows and (PR) policies, review processes reduce the risk of unauthorized change.
* **Disaster Recovery**: The entire infrastructure state is preserved in Git, enabling rapid reconstruction of entire environments from scratch.
* **Consistency Across Environments**: The same GitOps processes are applied across multiple environments (e.g., development, staging, and production environments), ensuring deployments are consistent.

## Essential GitOps Terminology

Throughout this post we'll encounter GitOps terminology that's essential to understand:
* **Reconciliation**: Comparing desired state (in Git) with actual state (in cluster) **and** applying corrections
* **Drift**: When the actual state of an environment deviates from what's defined in your desired state configuration (code in Git)
* **Self-Healing**: Automatic restoration of desired state when drift is detected
* **App of Apps Pattern**: This is actually not GitOps terminology but specific to ArgoCD and a pattern that enables an ArgoCD application to manage other applications.
* **Sync Policy**: Rules defining when and how ArgoCD should apply changes (manual vs automatic)
* **Prune**: Automatic removal of resources that no longer exist in Git (can be dangerous though ;-) )

## GitOps from scratch

We've already seen some core concepts of GitOps, but where to start?

First, we need a **Git Repository** that is going to contain all configuration files, manifests, and deployment definitinos. This repository becomes the authoritative source for our desired state.

Second, we need a **GitOps Operator**. We are going to use ArgoCD to operate our infrastructure.

At last, we need to have a **Target Environment**. This is the infrastructure where applications and configuration are deployed to. In most cases this will be Kubernetes, but it is also possible to control cloud resources and even traditional infrastructure.

### Basic GitOps workflow

The next steps are essential to apply configurations from our Git Repository through a GitOps Operator to our Target Environment:
1. **Configuration Change**: Modify configuration files in the Git repository
2. **Review Process**: Changes go through standard Git workflows (pull requests, code reviews, approvals)
3. **Automatic Detection**: The GitOps Operator detects changes in the repository
4. **Synchronization**: The operator applies changes to the target environment
5. **State Verification**: The operator continuously monitors and maintains the desired state

### Pre-requisites

Now you've a bit of understanding what GitOps is, we're going to install a GitOps environment ourselves. This blog post will assume you've access to a Kubernetes cluster and have some basic Kubernetes knowledge. If you don't, check out k3s and give it a try!

### Repository structure

First, we need a Git repository to store our GitOps configurations. My repository is available on [GitHub](https://github.com/piwi91/argocd-home-projects) and serves as the reference implementation throughout this post.

It has a simple but effective structure:
```
https://github.com/piwi91/argocd-home-projects/
├── apps/
│   └── $appname
│       └── kustomization.yaml # Application configuration using Kustomization (https://kustomize.io/)
├── argocd-appprojects/
│   └── project.yaml           # ArgoCD project definition
├── argocd-apps/
│   └── argocd.yaml            # ArgoCD application definition to manage itself
│   └── app.yaml               # Other application definitions
└── argocd/
    └── kustomization.yaml     # ArgoCD configuration
```

The structure allows me to add seperation between configuration but still have my entire infrastructure in a single repository.

### Security

Since configurations are stored in public Git repositories, implementing proper security measures is essential to protect infrastructure access and sensitive data. Two key components address these security requirements:
* **Dex**: An open-source, Kubernetes-native Identity Provider (IdP) that implements the OpenID Connect (OIDC) protocol. We use it to enable Single Sign-On (SSO) for our Argo applications and leveraging GitHub as Identity Provider.
* **Sealed Secrets**: A Kubernetes controller and tool developed by Bitnami that enables you to store encrypted secrets in Git repositories safely. It solves the fundamental problem of secret management in GitOps workflows where sensitive data like passwords, API keys, and certificates cannot be stored in plain text.

These security components are configured as part of the ArgoCD setup but won't be covered in detail here. For comprehensive information, refer to the [Dex documentation](https://dexidp.io/) and [Sealed Secret repository](https://github.com/bitnami-labs/sealed-secrets).

### Getting ArgoCD deployed to your Kubernetes cluster

I assume you already have access to a Kubernetes Cluster and that you've kubectl installed.

First, we create a namespace:
```
kubectl create namespace argocd
```

Second, we install ArgoCD using the official manifest:
```
kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

This will take some time. You can check if ArgoCD is ready using the kubectl wait command:
```
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --namespace argocd --timeout=300s
```

If ArgoCD is ready you will get a response like `pod/argocd-server-XXXXXXXXXX-XXXXX condition met`.

### Accessing ArgoCD for the first time

Use port forwarding to enable access to ArgoCD through the argocd-server service:
```
kubectl -n argocd port-forward svc/argocd-server -n argocd 8080:443
```

ArgoCD is password-protected by default. The initial admin password is stored in the argocd-initial-admin-secret secret. Retrieve the password to login:
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Navigate to https://localhost:8080 in your web browser and login with username `admin` and the retrieved password. The dashboard will be empty initially but will populate with applications after implementing the bootstrap configuration in the next steps.

### Bootstrap application projects and applications

Since everything can be managed through GitOps and ArgoCD, we implement the app-of-apps pattern using two bootstrap applications.

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-projects
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/piwi91/argocd-home-projects.git
    targetRevision: HEAD
    path: argocd-appprojects
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/piwi91/argocd-home-projects.git
    targetRevision: HEAD
    path: argocd-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
```

The `apps` application manages all applications defined in the argocd-apps directory, including an ArgoCD application that references the argocd directory containing the ArgoCD manifests and these same bootstrap applications. This creates a self-managing loop where:

1. **Initial Bootstrap**: You manually apply these two applications once
2. **Self-Management**: ArgoCD then manages its own configuration and all other applications
3. **Complete Automation**: Future changes only require Git commits and ArgoCD handles the rest

By adding more separation you can achieve more granular Role-Based Access Control (RBAC) if you like. Since I'm the only one configuring these environments, I left out these additional security layers.

### The ArgoCD configuration

The ArgoCD configuration is managed through an ArgoCD application that references the [argocd directory in my Git repository](https://github.com/piwi91/argocd-home-projects/tree/main/argocd). This setup uses [Kustomize](https://kustomize.io/), a Kubernetes-native tool for customizing YAML manifests without modifying the originals. Instead of duplicating and editing base files, Kustomize applies overlays and patches to customize configurations declaratively.

The ArgoCD Application to self-manage ArgoCD looks like this:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-cd
  namespace: argocd
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    path: argocd
    repoURL: https://github.com/piwi91/argocd-home-projects.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      selfHeal: true
```

The ArgoCD Application refers to the `argocd` directory in my personal Git repository that contains the Kustomize manifest file and will deploy the application into the `argocd` namespace. During the first synchronization, ArgoCD will reconciliate ensuring changes are applied to achieve the desired state.

The `kustomization.yaml` file in the `argocd` directory orchestrates the entire ArgoCD deployment:
```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd

resources:
  - base/argocd-namespace.yaml          # Creates the argocd namespace
  - base/argocd-repositories.yaml       # Registers repositories ArgoCD can access
  - base/argocd-applications.yaml       # Bootstraps applications in ArgoCD
  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.1.0/manifests/install.yaml  # ArgoCD base installation manifest

patches:
  - path: overlays/argocd-cm.yaml           # Additional core configuration
  - path: overlays/argocd-rbac-cm.yaml      # RBAC settings
  - path: overlays/argocd-cmd-params-cm.yaml # Extra command parameters
  - path: overlays/argocd-dex-server.yaml    # Environment variables for Dex SSO

images:
  - name: quay.io/argoproj/argocd
    newTag: v3.1.0
```

The `argocd-repositories.yaml` configures allowed Git repositories that ArgoCD can access as sources. This security measure ensures ArgoCD only pulls from trusted repositories. In this case, my personal Git repository serves as the single source of truth for all deployments.

### Other applications

Adding new applications is straightforward with the bootstrap pattern. Example Sealed Secrets application:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  destination:
    namespace: kube-system
    server: https://kubernetes.default.svc
  project: default
  source:
    path: apps/sealed-secrets
    repoURL: https://github.com/piwi91/argocd-home-projects.git
    targetRevision: HEAD
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    automated:
      selfHeal: true
      prune: true
```

Simply commit this file to the `argocd-apps` directory, and the bootstrap application will automatically deploy it.

## Conclusion

This self-managing ArgoCD setup provides complete automation through GitOps principles. All infrastructure changes flow through Git, ensuring consistency, auditability, and automated deployment. The system maintains itself while providing a foundation for managing all your applications and infrastructure through declarative configuration.

The complete configuration is available in the [example repository](https://github.com/piwi91/argocd-home-projects) for reference and adaptation to your specific needs.
