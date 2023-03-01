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

# Version Lock
KUBE_VERSION="1.23.16"
GO_VERSION="1.17.13"
CONTAINERD_VERSION="1.6.18"
RUNC_VERSION="1.1.4"
CNI_PLUGINS_VERSION="1.2.0"
KUBECTL_VERSION="1.23.16-00"
KUBEADM_VERSION="1.23.16-00"
KUBELET_VERSION="1.23.16-00"

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
ARCH=""
PROXY_CMD=""
KUBEADM_INIT_IMG_REPO_ARGS=""
TMP_DIR=""
OS=""
SYMBOL_WAITING=" >>>>> "

# Configure Redirection and Logs
exec 3>&1
exec 4>&2
exec 1>> easyOpenYurtInfo.log
exec 2>> easyOpenYurtErr.log

# Text Color Definition
COLOR_ERROR=1
COLOR_WARNING=3
COLOR_SUCCESS=2
COLOR_INFO=4
color_echo () {
    echo -e -n "$(tput setaf $1)[$(date +'%T')]\t$2$(tput sgr 0)"
}

# Print Helper Function
info_echo () {
	echo -e -n "[$(date +'%T')]\t[Info] $1" # For Logs
	color_echo ${COLOR_INFO} "[Info] $1" >&3 # For Output
}
success_echo () {
	echo -e -n "[$(date +'%T')]\t[Success] $1" # For Logs
	color_echo ${COLOR_SUCCESS} "[Success] $1" >&3 # For Output
}
warn_echo () {
	echo -e -n "[$(date +'%T')]\t[Warn] $1" >&2 # For Logs
	color_echo ${COLOR_WARNING} "[Warn] $1" >&4 # For Output
}
error_echo () {
	echo -e -n "[$(date +'%T')]\t[Error] $1" >&2 # For Logs
	color_echo ${COLOR_ERROR} "[Error] $1" >&4 # For Output
}
print_usage () {
	info_echo "Usage: $0 [object: system | kube | yurt] [nodeRole: master | worker] [operation: init | join | expand] <Args${SYMBOL_WAITING}>\n"
}

# Detect the Architecture
detect_arch () {
	ARCH=$(uname -m)
	case $ARCH in
		armv5*)	ARCH="armv5" ;;
		armv6*) ARCH="armv6" ;;
		armv7*) ARCH="arm" ;;
		aarch64) ARCH="arm64" ;;
		x86) ARCH="386" ;;
		x86_64) ARCH="amd64" ;;
		i686) ARCH="386" ;;
		i386) ARCH="386" ;;
		*)	terminate_with_error "Unsupported Architecture: ${ARCH}!" ;;
	esac
}

detect_os () {
	OS=$(cat /etc/issue | sed -n "s/\s*\(\S\S*\).*/\1/p" | head -1 | tr '[:upper:]' '[:lower:]')
}

# Detect Executable in PATH
detect_cmd () {
	cmd=$1
	if [ -x "$(command -v ${cmd})" ]; then
		return 0
	fi
	return 1
}


# Script Control
terminate_with_error () {
	funcArgc=$#
	errorMsg=$1
	if [ ${funcArgc} -ge 1 ]; then
		error_echo "${errorMsg}\n"
	fi
	error_echo "Script Terminated!\n"
	exit 1
}

terminate_if_error () {
	cmdResult=$?
	errorMsg=$1
	if ! [ ${cmdResult} -eq 0 ]; then
		error_echo "\n"
		terminate_with_error "${errorMsg}"
	else
		success_echo "\n"
	fi
}

exit_with_success_info () {
	funcArgc=$#
	exitMsg=$1
	if [ ${funcArgc} -ge 1 ]; then
		success_echo "${exitMsg}\n"
	fi
	exit 0
}

choose_yes () {
	msg=$1
	warn_echo "${msg} [y/n]: "
	read confirmation
	case ${confirmation} in
		[yY]*)
			return 0
		;;
		*)
			return 1
		;;
	esac
}


# Temporary Files Management
create_tmp_dir () {
	# Create Temporary Directory
	info_echo "Creating Temporary Directory${SYMBOL_WAITING}"
	mkdir -p ${HOME}/.yurt_tmp
	terminate_if_error "Failed to Create Temporary Directory!"
}

clean_tmp_dir () {
	# Clean Temporary Directory
	info_echo "Cleaning Temporary Directory${SYMBOL_WAITING}\n"
	rm -rf ${HOME}/.yurt_tmp
}

# Proxy Settings
use_proxychains () {
	# Use Proxychains If Existed
	if detect_cmd "proxychains"; then
		if choose_yes "Proxychains Detected! Use Proxy?"; then
			PROXY_CMD="proxychains"
			info_echo "Proxychains WILL be Used!\n"
		else
			info_echo "Proxychains WILL NOT be Used!\n"
		fi
		sleep 1
	fi
}

system_init () {
	# Disable Swap
	info_echo "Disabling Swap${SYMBOL_WAITING}"
	sudo swapoff -a && sudo cp /etc/fstab /etc/fstab.old 	# Turn off Swap && Backup fstab file
	terminate_if_error "Failed to Disable Swap!"

	info_echo "Modifying fstab${SYMBOL_WAITING}"
	sudo sed -i 's/.*swap.*/# &/g' /etc/fstab		# Modify fstab to Disable Swap Permanently
	terminate_if_error "Failed to Modify fstab!"

	# Install Dependencies
	info_echo "Installing Dependencies${SYMBOL_WAITING}"
	sudo ${PROXY_CMD} apt-get -qq update  && sudo ${PROXY_CMD} apt-get -qq install -y git wget curl build-essential apt-transport-https ca-certificates 
	terminate_if_error "Failed to Install Dependencies!"

	# Install Containerd
	info_echo "Installing Containerd(ver ${CONTAINERD_VERSION})${SYMBOL_WAITING}\n"
	info_echo "Downloading Containerd${SYMBOL_WAITING}"
	${PROXY_CMD} wget -q https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz 
	terminate_if_error "Failed to Download Containerd!"

	info_echo "Extracting Containerd${SYMBOL_WAITING}"
	sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
	terminate_if_error "Failed to Extract Containerd!"

	# Start Containerd via Systemd
	info_echo "Starting Containerd${SYMBOL_WAITING}"
	${PROXY_CMD} wget -q https://raw.githubusercontent.com/containerd/containerd/main/containerd.service && sudo cp containerd.service /lib/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now containerd
	terminate_if_error "Failed to Start Containerd!"

	# Install Runc
	info_echo "Installing Runc(ver ${RUNC_VERSION})${SYMBOL_WAITING}"
	${PROXY_CMD} wget -q https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH} && sudo install -m 755 runc.${ARCH} /usr/local/sbin/runc
	terminate_if_error "Failed to Install Runc!"

	# Install CNI Plugins
	info_echo "Installing CNI Plugins(ver ${CNI_PLUGINS_VERSION})${SYMBOL_WAITING}"
	${PROXY_CMD} wget -q https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz && sudo mkdir -p /opt/cni/bin && sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz
	terminate_if_error "Failed to Install CNI Plugins!"

	# Configure the Systemd Cgroup Driver
	info_echo "Configuring the Systemd Cgroup Driver${SYMBOL_WAITING}"
	containerd config default > config.toml && sudo mkdir -p /etc/containerd && sudo cp config.toml /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml && sudo systemctl restart containerd
	terminate_if_error "Failed to Configure the Systemd Cgroup Driver!"

	# Install Golang
	info_echo "Installing Golang(ver ${GO_VERSION})${SYMBOL_WAITING}"
	${PROXY_CMD} wget -q https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
	terminate_if_error "Failed to Install Golang!"

	# Update PATH
	info_echo "Updating PATH${SYMBOL_WAITING}\n"
	case ${SHELL} in
		/usr/bin/zsh | /bin/zsh | zsh)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.zshrc
		;;
		/usr/bin/bash | /bin/bash | bash)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.bashrc
		;;
		*)
			terminate_with_error "Unsupported Default Shell!"
		;;
	esac

	# Enable IP Forwading & Br_netfilter
	info_echo "Enabling IP Forwading & Br_netfilter${SYMBOL_WAITING}"
	sudo modprobe br_netfilter && sudo sysctl -w net.ipv4.ip_forward=1 # Enable IP Forwading & Br_netfilter instantly
	terminate_if_error "Failed to Enable IP Forwading & Br_netfilter!"

	info_echo "Ensuring Boot-Resistant${SYMBOL_WAITING}"
	echo "br_netfilter" | sudo tee /etc/modules-load.d/netfilter.conf && sudo sed -i 's/# *net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && sudo sed -i 's/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/g' /etc/sysctl.conf # Ensure Boot-Resistant
	terminate_if_error "Failed to Enable IP Forwading & Br_netfilter!"

	# Install Kubeadm, Kubelet, Kubectl
	info_echo "Downloading Google Cloud Public Signing Key${SYMBOL_WAITING}"
	sudo mkdir -p /etc/apt/keyrings && sudo ${PROXY_CMD} curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg  && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list # Download the Google Cloud public signing key && Add the Kubernetes apt repository
	terminate_if_error "Failed to Download the Google Cloud public signing key && Add the Kubernetes apt repository!"

	sudo apt-mark unhold kubelet kubeadm kubectl
	info_echo "Installing Kubeadm, Kubelet, Kubectl${SYMBOL_WAITING}"
	sudo ${PROXY_CMD} apt-get -qq update && sudo ${PROXY_CMD} apt-get -qq install -y --allow-downgrades kubeadm=${KUBEADM_VERSION} kubelet=${KUBELET_VERSION} kubectl=${KUBECTL_VERSION} && sudo apt-mark hold kubelet kubeadm kubectl
	terminate_if_error "Failed to Install Kubeadm, Kubelet, Kubectl!"
}

kubeadm_pre_pull () {
	# China Mainland Adaptation
	if choose_yes "Apply Adaptation & Optimization for China Mainland Users to Avoid Network Issues?"; then
		info_echo "Applying China Mainland Adaptation${SYMBOL_WAITING}\n"
		KUBEADM_INIT_IMG_REPO_ARGS="--image-repository docker.io/flyinghorse0510"
		sudo sed -i "s/sandbox_image = \".*\"/sandbox_image = \"docker.io/flyinghorse0510/pause:3.6\"/g" /etc/containerd/config.toml
	else
		info_echo "Adaptation WILL NOT be Applied!\n"
	fi

	# Pre-Pulling Required Images
	sudo kubeadm config images pull --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS}
}

kubeadm_master_init () {
	
	funcArgc=$#

	info_echo "kubeadm init${SYMBOL_WAITING}"
	if [ ${funcArgc} -eq 1 ]; then
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16" --apiserver-advertise-address=${apiserverAdvertiseAddress}
	else
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16"
	fi
	terminate_if_error "kubeadm init Failed!"

	# Make kubectl Work for Non-Root User
	info_echo "Making kubectl Work for Non-Root User${SYMBOL_WAITING}"
	mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
	terminate_if_error "Failed to Make kubectl Work for Non-Root User!"

	# Install Pod Network
	info_echo "Installing Pod Network${SYMBOL_WAITING}"
	${PROXY_CMD} kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
	terminate_if_error "Failed to Install Pod Network!"
}

kubeadm_worker_join () {
	# Join Kubernetes Cluster
	info_echo "Joining Kubernetes Cluster${SYMBOL_WAITING}"
	sudo kubeadm join ${controlPlaneHost}:${controlPlanePort} --token ${controlPlaneToken} --discovery-token-ca-cert-hash ${discoveryTokenHash}
	terminate_if_error "Failed to Join Kubernetes Cluster"
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

	# Install Helm
	info_echo "Installing Helm${SYMBOL_WAITING}\n"
}

# Check Arguments
if [ ${argc} -lt 3 ]; then
	print_usage
	terminate_with_error "Too Few Arguments!"
fi

# Process Arguments
case ${operationObject} in
	system)
		case ${nodeRole} in
			master | worker)
				if [ ${operation} != "init" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -ne 3 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					terminate_with_error "Invalid Arguments: Too Many Arguments!"
				fi
				system_init
				exit_with_success_info "Init System Successfully!"
			;;
			*)
				print_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
	;;
    kube)
		case ${nodeRole} in
			master)
				if [ ${operation} != "init" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -gt 4 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					terminate_with_error "Invalid Arguments: Too Many Arguments!"
				fi
				# kubeadm init
				kubeadm_pre_pull # Pre-Pull Required Images
				if [ ${argc} -eq 4 ]; then
					kubeadm_master_init ${apiserverAdvertiseAddress}
				else
					kubeadm_master_init
				fi
				exit_with_success_info "Init Kubernetes Cluster Master Node Successfully!"
			;;
			worker)
				if [ ${operation} != "join" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -ne 7 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
					terminate_with_error "Invalid Arguments: Need 7, Got ${argc}"
				fi
				# kubeadm join
				kubeadm_worker_join ${controlPlaneHost} ${controlPlanePort} ${controlPlaneToken} ${discoveryTokenHash}
				exit_with_success_info "Join Kubernetes Cluster Successfully!"
			;;
			*)
				print_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
    ;;
    yurt)
		case ${nodeRole} in
			master)
				case ${operation} in
					init)	terminate_with_error "Temporary Unavailable API!" ;;
					expand) terminate_with_error "Temporary Unavailable API!" ;;
					*)
						info_echo "Usage: $0 ${operationObject} ${nodeRole} [init | expand] <Args${SYMBOL_WAITING}>\n"
						terminate_with_error "Invalid Operation: [operation]->${operation}"
					;;
				esac
			;;
			worker)
				case ${operation} in
					join)
						if [ ${argc} -ne 6 ]; then
							info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
							terminate_with_error "Invalid Arguments: Need 6, Got ${argc}"
						fi
					;;
					*)
						info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
						terminate_with_error "Invalid Operation: [operation]->${operation}"
					;;
				esac
			;;
			*)
				print_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
    ;;
    *)
        print_usage
		terminate_with_error "Invalid Object: [object]->${operationObject}"
	;;
esac
