#!/bin/bash
# Text Color Definition
COLOR_ERROR=1
COLOR_WARNING=3
COLOR_SUCCESS=2
color_echo () {
	echo -e -n $(tput setaf $1) $2 $(tput sgr 0)
}

# Use Proxychains If Existed
PROXY_CMD=""
if [ -x "$(command -v proxychains)" ]; then
	color_echo ${COLOR_WARNING} "[Info]: Proxychains Detected! Use Proxy? [y/n]: "
	read confirmation
	case ${confirmation} in
		[yY]*)
			color_echo ${COLOR_SUCCESS} "[Info]: Proxychains WILL be Used!\n"
			PROXY_CMD="proxychains"
			;;
		*)
			color_echo ${COLOR_SUCCESS} "[Info]: Proxychains WILL NOT be Used!\n"
			;;
	esac
	sleep 1
fi

color_echo ${COLOR_SUCCESS} "[Info]: Installing Build Dependencies...\n"
sudo ${PROXY_CMD} apt update
sudo ${PROXY_CMD} apt install git wget build-essential curl

# Check Golang
if [ -x "$(command -v go)" ]; then
	color_echo ${COLOR_WARNING} "[Warning]: Golang Detected! Reinstall the Appropariate Version(1.13~1.17)? [y/n]: " 
	read confirmation
	case ${confirmation} in
		[yY]*)
			;;
		*)
			color_echo ${COLOR_WARNING} "[Warning]: Installation Aborted!\n"
			exit 0
			;;
	esac
fi

# Install Golang
color_echo ${COLOR_SUCCESS} "[Info]: Installing Golang(ver 1.17.13)\n"
mkdir -p ${HOME}/.yurt_tmp
pushd ${HOME}/.yurt_tmp
${PROXY_CMD} wget https://go.dev/dl/go1.17.13.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.17.13.linux-amd64.tar.gz

# Update PATH
export PATH=$PATH:/usr/local/go/bin
if [ -f ${HOME}/.bashrc ]; then
	echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.bashrc
fi
if [ -f ${HOME}/.zshrc ]; then
	echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.zshrc
fi

# Clone Source Code of yurtadm
color_echo ${COLOR_SUCCESS} "[Info]: Downloading Source Code and Compiling...\n"
${PROXY_CMD} git clone https://github.com/openyurtio/openyurt.git
pushd openyurt
${PROXY_CMD} make build WHAT="yurtadm" ARCH="amd64" REGION=cn
sudo cp _output/local/bin/linux/amd64/yurtadm /usr/local/bin/
popd
popd

# Clean Up
rm -rf ${HOME}/.yurt_tmp

# Check Installation
if [ -x "$(command -v yurtadm)" ]; then
	color_echo ${COLOR_SUCCESS} "[Info]: Successfully Installed yurtadm in /usr/local/bin/\n"
	exit 0
else
	color_echo ${COLOR_ERROR} "[Error]: Fatal Error! Installation Failed!\n"
	exit 1
fi
