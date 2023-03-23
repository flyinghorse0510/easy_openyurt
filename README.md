# EasyOpenYurt

## 1. Introduction

[OpenYurt](https://github.com/openyurtio/openyurt) is built based on upstream Kubernetes and has been designed to meet various DevOps requirements against typical edge infrastructures.

This program can help you to set up an OpenYurt cluster quickly and easily for development and test. It currently supports two main usages:

1. **From scratch**: Firstly set up a Kubernetes cluster using kubeadm and then deploy OpenYurt on it.
2. **Based on existing Kubernetes cluster**: Deploy OpenYurt directly on an existing Kubernetes cluster.

Additionally, several YAML template files which basically shows how to deploy services on OpenYurt are provided along with the program.

**Currently supported and tested platforms:**

|      OS      | ARCH  |
| :----------: | :---: |
| Ubuntu 22.04 | amd64 |
| Ubuntu 20.04 | amd64 |

**Currently supported and tested Shells:** `zsh`, `bash`

**<u>Warning:</u>** <u>This is an experimental program under development, **DO NOT** attempt to use it in production environment! Back up your system in advance to avoid possible damage.</u>

Finally, the program is well commented. You can look at the source and see what it is going to do before running. Have a good day!

## 2. Usage

**General Usage:**

```bash
./easy_openyurt <object: system | kube | yurt> <nodeRole: master | worker> <operation: init | join | expand> [Parameters...]
```

By default, **logs will be written into two files**: `easyOpenYurtCommon.log` and `easyOpenYurtError.log` **in the current directory**.

### 2.1 Get easy_openyurt

**You can either download the easy_openyurt binary file directly or build it from source**:

#### 2.1.1 Download the binary file directly

Go for [releases](https://github.com/flyinghorse0510/easy_openyurt/releases) and download the appropriate binary version.

#### 2.1.2 Build from source

**Building from source requires Golang(version at least 1.18) installed.**

```bash
git clone https://github.com/flyinghorse0510/easy_openyurt.git
cd easy_openyurt/
go build -o easy_openyurt ./src/easy_openyurt/*.go
```

### 2.2 Configure System on Master / Worker Node

> If you already have an existing kubernetes cluster, you can directly go to [2.4 Deploy OpenYurt on Kubernetes Cluster](#24-deploy-openyurt-on-kubernetes-cluster)

This procedure will install and configure required components in your system, such as:

- `containerd`
- `runc`
- `golang`
- `kubeadm`, `kubectl`, `kubelet`
- ……

To initialize your system, use the following command:

```bash
./easy_openyurt system master init # on the master node
./easy_openyurt system worker init # on the worker node
```

Additionally, if you want to change the version of components to be installed, you can add extra optional parameters behind(or add -h for help):

```bash
./easy_openyurt system master init -h
#### Output ####
# Usage of ./easy_openyurt system master init:
#   -cni-plugins-version string
#         CNI plugins version (default "1.2.0")
#   -containerd-version string
#         Containerd version (default "1.6.18")
#   -go-version string
#         Golang version (default "1.18.10")
#   -h    Show help
#   -help
#         Show help
#   -kubeadm-version string
#         Kubeadm version (default "1.23.16-00")
#   -kubectl-version string
#         Kubectl version (default "1.23.16-00")
#   -kubelet-version string
#         Kubelet version (default "1.23.16-00")
#   -runc-version string
#         Runc version (default "1.1.4")
```

### 2.3 Set up Kubernetes Cluster

#### 2.3.1 Set up Master Node

On master node, use the following command:

```bash
./easy_openyurt kube master init
```

By default, [the `kubeadm` uses the network interface associated with the default gateway to set the advertise address for this particular control-plane(master) node's API server](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/). To use a different network interface, provide an extra parameter to the program:

```bash
./easy_openyurt kube master init -apiserver-advertise-address [apiserverAdvertiseAddress]
# For example:
./easy_openyurt kube master init -apiserver-advertise-address 192.168.18.2
```

If everything goes well, you can find one file called `masterKey.yaml` in the current directory, which includes information that can be subsequently used to set up the worker node in Kubernetes cluster:

```yaml
# Content Template of `masterKey.yaml`
apiserverAdvertiseAddress: xxx.xxx.xxx.xxx
apiserverPort: xxxx
apiserverToken: xxxxxxxxxx
apiserverTokenHash: sha256:xxxxxxxxxx
```

To view the help and all available optional parameters, add `-h` to see more details:

```bash
./easy_openyurt kube master init -h
#### Output ####
# Usage of ./easy_openyurt kube master init:
#   -alternative-image-repo string
#         Alternative image repository
#   -apiserver-advertise-address string
#         Kubernetes API server advertise address
#   -h    Show help
#   -help
#         Show help
#   -k8s-version string
#         Kubernetes version (default "1.23.16")
```

#### 2.3.2 Set up Worker Node

On worker node, to join the Kubernetes cluster, use the following command:

```bash
./easy_openyurt kube worker join -apiserver-advertise-address <apiserverAdvertiseAddress> -apiserver-token <apiserverToken> -apiserver-token-hash <apiserverTokenHash>
# You can find these parameters in file `masterKey.yaml` previously introduced on the master node
# For Example:
./easy_openyurt kube worker join -apiserver-advertise-address 192.168.18.2 -apiserver-token xxxxxxxxxx -apiserver-token-hash sha256:xxxxxxxxxx
```

To view the help and all available optional parameters, add `-h` to see more details:

```bash
./easy_openyurt kube worker join -h
#### Output ####
# Usage of ./easy_openyurt kube worker join:
#   -apiserver-advertise-address string
#         Kubernetes API server advertise address (**REQUIRED**)
#   -apiserver-port string
#         Kubernetes API server port (default "6443")
#   -apiserver-token string
#         Kubernetes API server token (**REQUIRED**)
#   -apiserver-token-hash string
#         Kubernetes API server token hash (**REQUIRED**)
#   -h    Show help
#   -help
#         Show help
```

### 2.4 Deploy OpenYurt on Kubernetes Cluster

#### 2.4.1 Deploy on Master Node

On master node, to deploy OpenYurt, use the following command:

```bash
./easy_openyurt yurt master init
```

To view the help and all available optional parameters, add `-h` to see more details:

```bash
./easy_openyurt yurt master init -h
#### Output ####
# Usage of ./easy_openyurt yurt master init:
#   -h    Show help
#   -help
#         Show help
#   -master-as-cloud
#         Treat master as cloud node (default true)
```

#### 2.4.2 Deploy on Worker Node

**<u>Warning:</u>** <u>You should **ONLY** deploy OpenYurt on nodes that already have been joined in the Kubernetes cluster.</u>

##### 2.4.2.1 on the Worker Node

**<u>Firstly, on the worker node</u>**, use the following command:

```bash
./easy_openyurt yurt worker join -apiserver-advertise-address <apiserverAdvertiseAddress> -apiserver-token <apiserverToken>
# You can find these parameters in file `masterKey.yaml` previously introduced on the master node
# For Example:
./easy_openyurt yurt worker join -apiserver-advertise-address 192.168.18.2 -apiserver-token xxxxxxxxxx
```

To view the help and all available optional parameters, add `-h` to see more details:

```bash
./easy_openyurt yurt worker join -h
#### Output ####
# Usage of ./easy_openyurt yurt worker join:
#   -apiserver-advertise-address string
#         Kubernetes API server advertise address (**REQUIRED**)
#   -apiserver-port string
#         Kubernetes API server port (default "6443")
#   -apiserver-token string
#         Kubernetes API server token (**REQUIRED**)
#   -h    Show help
#   -help
#         Show help
```

##### 2.4.2.2 on the Master Node

**<u>Then, on the master node,</u>** use the following command:

```bash
./easy_openyurt yurt master expand -worker-node-name <nodeName> [-worker-as-edge]
# If you want to join the worker node as edge, specify the `-worker-as-edge` option
# <nodeName> is the name of the worker node that you want to join to the OpenYurt cluster
# For example:
./easy_openyurt yurt master expand -worker-node-name myEdgeNode0 -worker-as-edge
./easy_openyurt yurt master expand -worker-node-name myCloudNode0
```

To view the help and all available optional parameters, add `-h` to see more details:

```bash
./easy_openyurt yurt master expand -h
#### Output ####
# Usage of ./easy_openyurt yurt master expand:
#   -h    Show help
#   -help
#         Show help
#   -worker-as-edge
#         Treat worker as edge node (default true)
#   -worker-node-name string
#         Worker node name(**REQUIRED**)
```