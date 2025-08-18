---
date: "2023-08-24"
title: MetalLB, a bare metal Load Balancer for Kubernetes
slug: metallb-bare-metal-load-balancer-for-kubernetes
description: Running Kubernetes on bare metal can be challenging on several aspects. One of those is the use of load balancers. MetalLB is a bare metal load balancer that uses ARP to dynamically create new load balancers using dedicated internal IP addresses.
tags:
- kubernetes
- metallb
- networking
summary: Running Kubernetes on bare metal can be challenging on several aspects. One of those is the use of load balancers. MetalLB is a bare metal load balancer that uses ARP to dynamically create new load balancers using dedicated internal IP addresses.
---

## Kubernetes-at-home

Why would you ever run Kubernetes on bare-metal / physical servers you ask? Because I want to use Kubernetes at home! But yes, it comes with some challenges. One of the challenges most people will encounter pretty fast when they start with Kubernetes for the first time is the learning curve. Kubernetes is not a technology that you master in a few hours, for sure if you want to understand how things work under the hood. In my case I already have several years of experience with Kubernetes which helps me setting things rather quick. But running a bare-metal instance of Kubernetes has some more challenges. Cloud providers like Azure, AWS, and Google provide you with softare defined networking and storage on demand (e.g. Azure Blob Storage, Amazon S3, or Google Cloud Storage). On bare-metal you just don't and you've to set this up yourself. One of those tools that definitely helps you running Kubernetes on a bare-metal server (at home or in the office) is MetalLB!

## MetalLB

MetalLB is a bare metal load balancer technology that uses ARP requests to claim an IP address without the need of configuring multiple IP addresses on your NIC or the need of fancy network devices. All traffic goes to the node that reponds to the ARP request. From there, the `kube-proxy` routes the traffic to the pods. In that sense, MetalLB is not really a load balancer but has failover capabilities that if a node fails another node takes over the IP addresses.

Besides ARP-mode, MetalLB also supports BGP routing en FRR. I won't cover BGP routing in this blog post because I don't run a BGP network at home ;-).

### How to install it

MetalLB requires little configuration. The only thing you need is IP address range. Make sure the IP address range you're going to use is not in use! Don't forget it to exclude it from the DHCP range for instance. Devices using the same IP address will give you a hard time debugging!

I've installed MetalLB using a Helm Chart. The Helm Chart installation is the recommended way to install MetalLB on your Kubernetes instance. Copy the code below to install MetalLB in its own namespace.

```bash
helm repo add metallb https://metallb.github.io/metallb
helm upgrade metallb metallb/metallb \
  --create-namespace \
  --namespace metallb-system \
  --wait
```

You probably noted the `--wait` parameters in the command above. This is because I setup MetalLB using a shell script that includes two more configurations that we need. Without configuring an IP address pool and L2 advertisement configuration, MetalLB won't do anything.

Create an `ipaddresspool.yaml` file with the content below. Change the addresses to the address space you've reserved for MetalLB.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.1-192.168.0.100
  - 192.168.0.0/25
```

Create another file to add the L2 advertisement. In my configuration I named it ... `l2advertisement.yaml`!

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-pool-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - local-pool
```

Apply both configurations using `kubectl`.

```bash
kubectl apply -f ipaddresspool.yaml
kubectl apply -f l2advertisement.yaml
```

Check if the MetalLB controller is running.

```bash
kubectl -n metallb-system get all
```

Example result:

```bash
NAME                                      READY   STATUS    RESTARTS       AGE
pod/metallb-controller-5cd9b4944b-5j4g9   1/1     Running   3 (49m ago)    36h
pod/metallb-speaker-5262n                 4/4     Running   33 (49m ago)   36h

NAME                              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/metallb-webhook-service   ClusterIP   10.43.96.229   <none>        443/TCP   36h

NAME                             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/metallb-speaker   1         1         1       1            1           kubernetes.io/os=linux   36h

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/metallb-controller   1/1     1            1           36h

NAME                                            DESIRED   CURRENT   READY   AGE
replicaset.apps/metallb-controller-5cd9b4944b   1         1         1       36h
```

### How to use it

Now MetalLB is installed and running we're able to expose a pod using a load balancer service. I'm going to deploy a Nginx instance first and then expose it using a service.

```bash
kubectl create deployment nginx --image=nginx  --port=80
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx
  annotations:
    metallb.universe.tf/loadBalancerIPs: xxx.xxx.xxx.xxx
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx
  type: LoadBalancer
EOF
```

In the above example I use the annotation `metallb.universe.tf/loadBalancerIPs` to use a specific IP address. This is not required if you don't care about which IP address is used.

**Note:** The `spec.loadBalancerIP` is also respected but is deprecated!

Check using `kubectl` if the load balancer is created and active.

```bash
kubectl get svc
NAME                         TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                                                                      AGE
nginx                        LoadBalancer   10.43.64.169    xxx.xxx.xxx.xxx 80:32047/TCP                                                                 5s
```

Success! Go the `http://xxx.xxx.xxx.xxx` to check the default page of your Nginx instance.

### Known issues

If you encounter any issues check out the [MetalLB troubleshoot page](https://metallb.universe.tf/troubleshooting/) first. There are also some known issues for [K3s](https://metallb.universe.tf/configuration/k3s/), [Calico](https://metallb.universe.tf/configuration/calico/), [Weave](https://metallb.universe.tf/configuration/weave/), and [kube-route](https://metallb.universe.tf/configuration/kube-router/).

### IP address sharing

Re-use IP addresses for multiple Load Balancer services is often used. For instance when running a `pihole` instance that creates two services that have to share an IP address. Fortunately shareing IP addresses is possible by adding the `metallb.universe.tf/allow-shared-ip: "key-to-share-1.2.3.4"` annotation. The `key-to-share-1.2.3.4` needs to be equal to all services that share an IP address.

### Multiple IP pools

When you have multiple IP pools configured you can use the `metallb.universe.tf/address-pool: production-public-ips` annotation to specify a specific pool.

## Recap

Running a bare-metal Kubernetes cluster with support of Load Balancers is perfectly possible using MetalLB. After creating an IP pool and L2 advertisement you are good to go. Exposing applications on a bare-metal Kubernetes cluster using Load Balancer services won't become easier than this. Give it a try!