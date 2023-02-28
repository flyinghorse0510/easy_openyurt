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

# Receive Parameters
nodeRole=$1
nodeType=$2
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

# Use Proxychains If Existed
PROXY_CMD=""
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

# Install Dependencies
info_echo "Installing Dependencies...\n"
sudo ${PROXY_CMD} apt -qq update > /dev/null && sudo ${PROXY_CMD} apt -qq install -y git wget curl build-essential apt-transport-https ca-certificates > /dev/null
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
${PROXY_CMD} wget https://github.com/containerd/containerd/releases/download/v1.6.18/containerd-1.6.18-linux-${ARCH}.tar.gz > /dev/null
if ! [ $? -eq 0 ]; then
        error_echo "Failed to Download Containerd!\n"
        error_echo "Script Terminated!\n"
	exit 1
fi
info_echo "Installing Containerd...\n"
sudo tar Cxzvf /usr/local containerd-1.6.18-linux-${ARCH}.tar.gz > /dev/null
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
${PROXY_CMD} wget https://github.com/opencontainers/runc/releases/download/v1.1.4/runc.${ARCH} > /dev/null && sudo install -m 755 runc.${ARCH} /usr/local/sbin/runc
if ! [ $? -eq 0 ]; then
        error_echo "Failed to Install Runc!\n"
        error_echo "Script Terminated!\n"
        exit 1
fi

# Install CNI Plugins
info_echo "Installing CNI Plugins...\n"
${PROXY_CMD} wget https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-${ARCH}-v1.2.0.tgz > /dev/null && sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-${ARCH}-v1.2.0.tgz > /dev/null
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
info_echo "Installing Golang(ver 1.17.13)...\n"
${PROXY_CMD} wget https://go.dev/dl/go1.17.13.linux-${ARCH}.tar.gz > /dev/null && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.17.13.linux-${ARCH}.tar.gz > /dev/null
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
sudo ${PROXY_CMD} apt -qq update > /dev/null && sudo ${PROXY_CMD} apt -qq install -y --allow-downgrades kubeadm=1.23.16-00 kubelet=1.23.16-00 kubectl=1.23.16-00 > /dev/null && sudo apt-mark hold kubelet kubeadm kubectl
if ! [ $? -eq 0 ]; then
        error_echo "Failed to Install Kubeadm, Kubelet, Kubectl!\n"
        error_echo "Script Terminated!\n"
        exit 1
fi

# China Mainland Adaptation
KUBEADM_INIT_IMG_REPO_ARGS=""
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


kubeadm_master_init () {
}

kubeadm_worker_join () {
}

case ${nodeRole} in
	master)
		kubeadm_master_init ${apiserverAdvertiseAddress} ${KUBEADM_INIT_IMG_REPO_ARGS}
		;;
	worker)
		kubeadm_worker_join 
		;;
# Kubeadm init
popd
