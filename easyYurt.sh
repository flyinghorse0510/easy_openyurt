#!/bin/bash

# MIT License
# 
# Copyright (c) 2023 Haoyuan Ma

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Text Color Definition
COLOR_ERROR=1
COLOR_WARNING=3
COLOR_SUCCESS=2
color_echo () {
        echo -e -n $(tput setaf $1)$2$(tput sgr 0)
}
warn_echo () {
	color_echo ${COLOR_WARNING} "[Warn] $1"
}
info_echo () {
	color_echo ${COLOR_SUCCESS} "[Info] $1"
}
error_echo () {
	color_echo ${COLOR_ERROR} "[Error] $1"
}

# Global Variables
argc=$#
operationObject=$1
nodeRole=$2
operation=$3
apiserverAdvertiseAddress=$4
controlPlaneHost=$4
controlPlanePort=$5
controlPlaneToken=$6
discoveryTokenHash=$7
PROXY_CMD=""
KUBEADM_INIT_IMG_REPO_ARGS=""

# Version Information
KUBE_VERSION="1.23.16"
GO_VERSION="1.17.13"
CONTAINERD_VERSION="1.6.18"
RUNC_VERSION="1.1.4"
CNI_PLUGINS_VERSION="1.2.0"
KUBECTL_VERSION="1.23.16-00"
KUBEADM_VERSION="1.23.16-00"
KUBELET_VERSION="1.23.16-00"

print_usage () {
	info_echo "Usage: $0 [object: system | kube | yurt] [nodeRole: master | worker] [operation: init | join | expand] <Args...>\n"
}

system_init () {
	# Disable Swap
	info_echo "Disabling Swap...\n"
	sudo swapoff -a && sudo cp /etc/fstab /etc/fstab.old 	# Turn off Swap && Backup fstab file
	if ! [ $? -eq 0 ]; then
		error_echo "Failed to Disable Swap!\n"
		error_echo "Script Terminated!\n"
		exit 1
	fi
	sudo sed -i 's/.*swap.*/# &/g' /etc/fstab		# Modify fstab to Disable Swap Permanently
	if ! [ $? -eq 0 ]; then
		error_echo "Failed to Modify fstab!\n"
		error_echo "Script Terminated!\n"
		exit 1
	fi

	# Install Dependencies
	info_echo "Installing Dependencies...\n"
	sudo ${PROXY_CMD} apt-get -qq update > /dev/null && sudo ${PROXY_CMD} apt-get -qq install -y git wget curl build-essential apt-transport-https ca-certificates > /dev/null
	if ! [ $? -eq 0 ]; then
		error_echo "Failed to Install Dependencies!\n"
		error_echo "Script Terminated!\n"
		exit 1
	fi

	# Create Temporary Directory
	info_echo "Creating Temporary Directory...\n"
	mkdir -p ${HOME}/.yurt_tmp
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Create Temporary Directory!\n"
        	error_echo "Script Terminated!\n"
		exit 1
	fi

	# Install Containerd
	ARCH=$(dpkg --print-architecture)
	pushd ${HOME}/.yurt_tmp
	info_echo "Downloading Containerd...\n"
	${PROXY_CMD} wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz > /dev/null
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Download Containerd!\n"
        	error_echo "Script Terminated!\n"
		exit 1
	fi
	info_echo "Installing Containerd...\n"
	sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz > /dev/null
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Install Containerd!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Start Containerd via Systemd
	info_echo "Starting Containerd...\n"
	${PROXY_CMD} wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service > /dev/null && sudo cp containerd.service /lib/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now containerd
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Start Containerd!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Install Runc
	info_echo "Installing Runc...\n"
	${PROXY_CMD} wget https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH} > /dev/null && sudo install -m 755 runc.${ARCH} /usr/local/sbin/runc
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Install Runc!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Install CNI Plugins
	info_echo "Installing CNI Plugins...\n"
	${PROXY_CMD} wget https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz > /dev/null && sudo mkdir -p /opt/cni/bin && sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz > /dev/null
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Install CNI Plugins!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Configure the Systemd Cgroup Driver
	info_echo "Configuring the Systemd Cgroup Driver...\n"
	containerd config default > config.toml && sudo mkdir -p /etc/containerd && sudo cp config.toml /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml && sudo systemctl restart containerd
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Configure the Systemd Cgroup Driver!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Install Golang
	info_echo "Installing Golang(ver ${GO_VERSION})...\n"
	${PROXY_CMD} wget https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz > /dev/null && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz > /dev/null
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Install Golang!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Update PATH
	info_echo "Updating PATH...\n"
	case ${SHELL} in
		/usr/bin/zsh | /bin/zsh | zsh)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.zshrc
			;;
		/usr/bin/bash | /bin/bash | bash)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.bashrc
			;;
		*)
			error_echo "Unsupported Default Shell!\n"
			error_echo "Script Terminated!\n"
			exit 1
			;;
	esac

	# Enable IP Forwading & Br_netfilter
	info_echo "Enabling IP Forwading & Br_netfilter...\n"
	sudo modprobe br_netfilter && sudo sysctl -w net.ipv4.ip_forward=1 # Enable IP Forwading & Br_netfilter instantly
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Enable IP Forwading & Br_netfilter!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi
	echo "br_netfilter" | sudo tee /etc/modules-load.d/netfilter.conf && sudo sed -i 's/# *net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && sudo sed -i 's/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/g' /etc/sysctl.conf # Ensure Boot-Resistant
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Enable IP Forwading & Br_netfilter!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Install Kubeadm, Kubelet, Kubectl
	info_echo "Installing Kubeadm, Kubelet, Kubectl...\n"
	sudo mkdir -p /etc/apt/keyrings && sudo ${PROXY_CMD} curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg > /dev/null && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list # Download the Google Cloud public signing key && Add the Kubernetes apt repository
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Download the Google Cloud public signing key && Add the Kubernetes apt repository!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi
	sudo apt-mark unhold kubelet kubeadm kubectl 2> /dev/null
	sudo ${PROXY_CMD} apt-get -qq update > /dev/null && sudo ${PROXY_CMD} apt-get -qq install -y --allow-downgrades kubeadm=${KUBEADM_VERSION} kubelet=${KUBELET_VERSION} kubectl=${KUBECTL_VERSION} > /dev/null && sudo apt-mark hold kubelet kubeadm kubectl
	if ! [ $? -eq 0 ]; then
        	error_echo "Failed to Install Kubeadm, Kubelet, Kubectl!\n"
        	error_echo "Script Terminated!\n"
        	exit 1
	fi

	# Clean Temporary Directory
	info_echo "Cleaning Temporary Directory...\n"
	popd
	rm -rf ${HOME}/.yurt_tmp
}

kubeadm_pre_pull () {
	# China Mainland Adaptation
        warn_echo "Apply Adaptation & Optimization for China Mainland Users to Avoid Network Issues? [y/n]: "
        read confirmation
        case ${confirmation} in
                [yY]*)
                        warn_echo "Applying China Mainland Adaptation...\n"
                        KUBEADM_INIT_IMG_REPO_ARGS="--image-repository docker.io/flyinghorse0510"
                        sudo sed -i "s/sandbox_image = \".*\"/sandbox_image = \"docker.io/flyinghorse0510/pause:3.6\"/g" /etc/containerd/config.toml
                        ;;
                *)
                        warn_echo "Adaptation WILL NOT be Applied!\n"
                        ;;
        esac
	# Pre-Pulling Required Images
	sudo kubeadm config images pull --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS}
}

kubeadm_master_init () {
	
	funcArgc=$#

	if [ ${funcArgc} -eq 1 ]; then
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16" --apiserver-advertise-address=${apiserverAdvertiseAddress}
	else
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16"
	fi
	if ! [ $? -eq 0 ]; then
		error_echo "kubeadm init Failed!\n"
		error_echo "Script Terminated!\n"
		exit 1
	fi

	# Make kubectl Work for Non-Root User
	info_echo "Making kubectl Work for Non-Root User...\n"
	mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
	if ! [ $? -eq 0 ]; then
                error_echo "Failed to Make kubectl Work for Non-Root User!\n"
                error_echo "Script Terminated!\n"
                exit 1
        fi

	# Install Pod Network
	info_echo "Installing Pod Network...\n"
	${PROXY_CMD} kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
	if ! [ $? -eq 0 ]; then
                error_echo "Failed to Install Pod Network!\n"
                error_echo "Script Terminated!\n"
                exit 1
        fi
}

kubeadm_worker_join () {
	# Join Kubernetes Cluster
	info_echo "Joining Kubernetes Cluster...\n"
	sudo kubeadm join ${controlPlaneHost}:${controlPlanePort} --token ${controlPlaneToken} --discovery-token-ca-cert-hash sha256:${discoveryTokenHash}
	if ! [ $? -eq 0 ]; then
                error_echo "Failed to Join Kubernetes Cluster\n"
                error_echo "Script Terminated!\n"
                exit 1
        fi
}

yurt_master_init () {
	# Whether to Treat Master Node as a Cloud Node
	warn_echo "Treat Master Node as a Cloud Node? [y/n]: "
	read confirmation
	case ${confirmation} in
		[yY]*)
			kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-
			kubectl taint nodes --all node-role.kubernetes.io/control-plane-
			warn_echo "Master Node WILL also be Treated as a Cloud Node\n"
			;;
		*)
			warn_echo "Master Node WILL NOT be Treated as a Cloud Node\n"
			;;
	esac
}

# Check Arguments
if [ ${argc} -lt 3 ]; then
        error_echo "Too Few Arguments!\n"
        print_usage
        exit 1
fi

# Use Proxychains If Existed
if [ -x "$(command -v proxychains)" ]; then
        warn_echo "Proxychains Detected! Use Proxy? [y/n]: "
        read confirmation
        case ${confirmation} in
                [yY]*)
                        info_echo "Proxychains WILL be Used!\n"
                        PROXY_CMD="proxychains"
                        ;;
                *)
                        info_echo "Proxychains WILL NOT be Used!\n"
                        ;;
        esac
        sleep 1
fi

# Process Arguments
case ${operationObject} in
	system)
		case ${nodeRole} in
			master | worker)
				if [ ${operation} != "init" ]; then
					error_echo "Invalid Operation: [operation]->${operation}\n"
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					exit 1
				fi
				if [ ${argc} -ne 3 ]; then
					error_echo "Invalid Arguments: Too Many Arguments!\n"
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					exit 1
				fi
				system_init
				info_echo "Init System Successfully!\n"
				exit 0
				;;
			*)
				error_echo "Invalid NodeRole: [nodeRole]->${nodeRole}\n"
				print_usage
				exit 1
				;;
		esac
		;;
        kube)
		case ${nodeRole} in
			master)
				if [ ${operation} != "init" ]; then
					error_echo "Invalid Operation: [operation]->${operation}\n"
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					exit 1
				fi
				if [ ${argc} -gt 4 ]; then
					error_echo "Invalid Arguments: Too Many Arguments!\n"
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					exit 1
				fi
				# kubeadm init
				kubeadm_pre_pull # Pre-Pull Required Images
				if [ ${argc} -eq 4 ]; then
					kubeadm_master_init ${apiserverAdvertiseAddress}
				else
					kubeadm_master_init
				fi
				info_echo "Init Kubernetes Cluster Master Node Successfully!\n"
				exit 0
				;;
			worker)
				if [ ${operation} != "join" ]; then
                                        error_echo "Invalid Operation: [operation]->${operation}\n"
                                        info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
                                        exit 1
                                fi
				if [ ${argc} -ne 7 ]; then
					error_echo "Invalid Arguments: Need 7, Got ${argc}\n"
					info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
					exit 1
				fi
				# kubeadm join
				kubeadm_worker_join ${controlPlaneHost} ${controlPlanePort} ${controlPlaneToken} ${discoveryTokenHash}
				info_echo "Join Kubernetes Cluster Successfully!\n"
				exit 0
				;;
			*)
				error_echo "Invalid NodeRole: [nodeRole]->${nodeRole}\n"
				print_usage
				exit 1
				;;
		esac
                ;;
        yurt)
		case ${nodeRole} in
			master)
				case ${operation} in
					init)
						error_echo "Temporary Unavailable API!\n"
						exit 1
						;;
					expand)
						error_echo "Temporary Unavailable API!\n"
                                                exit 1
						;;
					*)
						error_echo "Invalid Operation: [operation]->${operation}\n"
						info_echo "Usage: $0 ${operationObject} ${nodeRole} [init | expand] <Args...>\n"
						exit 1
						;;
				esac
				;;
			worker)
				case ${operation} in
					join)
						if [ ${argc} -ne 6 ]; then
							error_echo "Invalid Arguments: Need 6, Got ${argc}\n"
							info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
							exit 1
						fi
						;;
					*)
						error_echo "Invalid Operation: [operation]->${operation}\n"
						info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
						exit 1
						;;
				esac
				;;
			*)
				error_echo "Invalid NodeRole: [nodeRole]->${nodeRole}\n"
				print_usage
				exit 1
				;;
		esac
                ;;
        *)
                error_echo "Invalid Object: [object]->${operationObject}\n"
                print_usage
		exit 1
		;;
esac
