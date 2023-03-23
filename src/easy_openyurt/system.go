// Author: Haoyuan Ma <flyinghorse0510@zju.edu.cn>
package main

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path"
	"runtime"
	"strings"
)

// System environment struct
type SystemEnvironment struct {
	goInstalled                         bool
	containerdInstalled                 bool
	runcInstalled                       bool
	cniPluginsInstalled                 bool
	systemdStartUp                      bool
	goVersion                           string
	goDownloadUrlTemplate               string
	containerdVersion                   string
	containerdDownloadUrlTemplate       string
	containerdSystemdProfileDownloadUrl string
	runcVersion                         string
	runcDownloadUrlTemplate             string
	cniPluginsVersion                   string
	cniPluginsDownloadUrlTemplate       string
	kubectlVersion                      string
	kubeadmVersion                      string
	kubeletVersion                      string
	dependencies                        string
	tmpDir                              string
}

// Implement error interface of ShellError
type ShellError struct {
	msg      string
	exitCode int
}

func (err *ShellError) Error() string {
	return fmt.Sprintf("[exit %d] -> %s", err.exitCode, err.msg)
}

// Current OS
var currentOS = runtime.GOOS

// Current arch
var currentArch = runtime.GOARCH

// Current directory
var currentDir = ""

// Current home directory
var userHomeDir = ""

// Current system environment
var systemEnvironment = SystemEnvironment{
	goInstalled:                         false,
	containerdInstalled:                 false,
	runcInstalled:                       false,
	cniPluginsInstalled:                 false,
	systemdStartUp:                      true,
	goVersion:                           "1.18.10",
	goDownloadUrlTemplate:               "https://go.dev/dl/go%s.linux-%s.tar.gz",
	containerdVersion:                   "1.6.18",
	containerdDownloadUrlTemplate:       "https://github.com/containerd/containerd/releases/download/v%s/containerd-%s-linux-%s.tar.gz",
	containerdSystemdProfileDownloadUrl: "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service",
	runcVersion:                         "1.1.4",
	runcDownloadUrlTemplate:             "https://github.com/opencontainers/runc/releases/download/v%s/runc.%s",
	cniPluginsVersion:                   "1.2.0",
	cniPluginsDownloadUrlTemplate:       "https://github.com/containernetworking/plugins/releases/download/v%s/cni-plugins-linux-%s-v%s.tgz",
	kubectlVersion:                      "1.23.16-00",
	kubeadmVersion:                      "1.23.16-00",
	kubeletVersion:                      "1.23.16-00",
}

// Parse parameters for subcommand `system`
func ParseSubcommandSystem(args []string) {
	nodeRole := args[0]
	operation := args[1]

	// Check nodeRole
	if (nodeRole != "master") && (nodeRole != "worker") {
		InfoPrintf("Usage: %s %s <master | worker> init [parameters...]\n", os.Args[0], os.Args[1])
		FatalPrintf("Invalid nodeRole: <nodeRole> -> %s\n", nodeRole)
	}

	// Check operation
	if operation != "init" {
		InfoPrintf("Usage: %s %s %s init [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
		FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
	}

	// Parse parameters for `system master/worker init`
	var help bool
	systemFlagsName := fmt.Sprintf("%s system %s init", os.Args[0], nodeRole)
	systemFlags := flag.NewFlagSet(systemFlagsName, flag.ExitOnError)
	systemFlags.StringVar(&systemEnvironment.goVersion, "go-version", systemEnvironment.goVersion, "Golang version")
	systemFlags.StringVar(&systemEnvironment.containerdVersion, "containerd-version", systemEnvironment.containerdVersion, "Containerd version")
	systemFlags.StringVar(&systemEnvironment.runcVersion, "runc-version", systemEnvironment.runcVersion, "Runc version")
	systemFlags.StringVar(&systemEnvironment.cniPluginsVersion, "cni-plugins-version", systemEnvironment.cniPluginsVersion, "CNI plugins version")
	systemFlags.StringVar(&systemEnvironment.kubectlVersion, "kubectl-version", systemEnvironment.kubectlVersion, "Kubectl version")
	systemFlags.StringVar(&systemEnvironment.kubeadmVersion, "kubeadm-version", systemEnvironment.kubeadmVersion, "Kubeadm version")
	systemFlags.StringVar(&systemEnvironment.kubeletVersion, "kubelet-version", systemEnvironment.kubeletVersion, "Kubelet version")
	systemFlags.BoolVar(&help, "help", false, "Show help")
	systemFlags.BoolVar(&help, "h", false, "Show help")
	systemFlags.Parse(args[2:])
	// Show help
	if help {
		systemFlags.Usage()
		os.Exit(0)
	}
	SystemInit()
	SuccessPrintf("Init System Successfully!\n")
}

// Execute Shell Command
func ExecShellCmd(cmd string, pars ...any) (string, error) {
	// Allocate bytes buffer
	bashCmd := new(bytes.Buffer)
	cmdStdout := new(bytes.Buffer)
	cmdStderr := new(bytes.Buffer)
	fmt.Fprintf(bashCmd, cmd, pars...)
	bashProcess := exec.Command("bash", "-c", bashCmd.String())
	// Redirect stdout & stderr
	bashProcess.Stdout = cmdStdout
	bashProcess.Stderr = cmdStderr

	// Execute command
	err := bashProcess.Run()

	// remove suffix "\n" in Stdout & Stderr
	var trimmedStdout string
	var trimmedStderr string
	if cmdStdout.Len() > 0 {
		trimmedStdout = strings.TrimSuffix(cmdStdout.String(), "\n")
	} else {
		trimmedStdout = ""
	}
	if cmdStderr.Len() > 0 {
		trimmedStderr = strings.TrimSuffix(cmdStderr.String(), "\n")
	} else {
		trimmedStderr = ""
	}

	// Rewrite error message
	if err != nil {
		err = &ShellError{msg: trimmedStderr, exitCode: bashProcess.ProcessState.ExitCode()}
	}

	// For logs
	if commonLog != nil {
		commonLog.Printf("Executing shell command: %s\n", bashCmd.String())
		commonLog.Printf("Stdout from shell:\n%s\n", trimmedStdout)
	}
	if errorLog != nil {
		errorLog.Printf("Executing shell command: %s\n", bashCmd.String())
		errorLog.Printf("Stderr from shell:\n%s\n", trimmedStderr)
	}

	return trimmedStdout, err
}

// Detect current architecture
func DetectArch() {
	switch currentArch {
	default:
		InfoPrintf("Detected Arch: %s\n", currentArch)
	}
}

// Detect current operating system
func DetectOS() {
	switch currentOS {
	case "windows":
		FatalPrintf("Unsupported OS: %s\n", currentOS)
	default:
		var err error
		currentOS, err = ExecShellCmd("sed -n 's/^NAME=\"\\(.*\\)\"/\\1/p' < /etc/os-release | head -1 | tr '[:upper:]' '[:lower:]'")
		CheckErrorWithMsg(err, "Failed to get Linux distribution info!\n")
		switch currentOS {
		case "ubuntu":
		default:
			FatalPrintf("Unsupported Linux distribution: %s\n", currentOS)
		}
		InfoPrintf("Detected OS: %s\n", strings.TrimSuffix(string(currentOS), "\n"))
	}
}

// Get current directory
func GetCurrentDir() {
	var err error
	currentDir, err = os.Getwd()
	CheckErrorWithMsg(err, "Failed to get get current directory!\n")
}

// Get current home directory
func GetUserHomeDir() {
	var err error
	userHomeDir, err = os.UserHomeDir()
	CheckErrorWithMsg(err, "Failed to get current home directory!\n")
}

// Create temporary directory
func CreateTmpDir() {
	var err error
	WaitPrintf("Creating temporary directory")
	systemEnvironment.tmpDir, err = os.MkdirTemp("", "yurt_tmp")
	CheckErrorWithTagAndMsg(err, "Failed to create temporary directory!\n")
}

// Clean up temporary directory
func CleanUpTmpDir() {
	WaitPrintf("Cleaning up temporary directory")
	err := os.RemoveAll(systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to create temporary directory!\n")
}

// Download file to temporary directory (absolute path of downloaded file will be the first return value if successful)
func DownloadToTmpDir(urlTemplate string, pars ...any) (string, error) {
	url := fmt.Sprintf(urlTemplate, pars...)
	fileName := path.Base(url)
	filePath := systemEnvironment.tmpDir + "/" + fileName
	_, err := ExecShellCmd("curl -sSL --output %s %s", filePath, url)
	return filePath, err
}

// Install packages on various OS
func InstallPackages(packagesTemplate string, pars ...any) error {
	packages := fmt.Sprintf(packagesTemplate, pars...)
	switch currentOS {
	case "ubuntu":
		_, err := ExecShellCmd("sudo apt-get -qq update && sudo apt-get -qq install -y --allow-downgrades %s", packages)
		return err
	case "centos":
		_, err := ExecShellCmd("sudo dnf -y -q install %s", packages)
		return err
	case "rocky linux":
		_, err := ExecShellCmd("sudo dnf -y -q install %s", packages)
		return err
	default:
		FatalPrintf("Unsupported Linux distribution: %s\n", currentOS)
		return &ShellError{msg: "Unsupported Linux distribution", exitCode: 1}
	}
}

// Turn off unattended-upgrades
func TurnOffAutomaticUpgrade() (string, error) {
	switch currentOS {
	case "ubuntu":
		_, err := os.Stat("/etc/apt/apt.conf.d/20auto-upgrades")
		if err == nil {
			return ExecShellCmd("sudo sed -i 's/\"1\"/\"0\"/g' /etc/apt/apt.conf.d/20auto-upgrades")
		}
		return "", nil
	default:
		return "", nil
	}
}

// Check system environment
func CheckSystemEnvironment() {
	// Check system environment
	InfoPrintf("Checking system environment...\n")
	var err error

	// Check Golang
	_, err = exec.LookPath("go")
	if err != nil {
		WarnPrintf("Golang not found! Golang(version %s) will be automatically installed!\n", systemEnvironment.goVersion)
	} else {
		SuccessPrintf("Golang found!\n")
		systemEnvironment.goInstalled = true
	}

	// Check Containerd
	_, err = exec.LookPath("containerd")
	if err != nil {
		WarnPrintf("Containerd not found! containerd(version %s) will be automatically installed!\n", systemEnvironment.containerdVersion)
	} else {
		SuccessPrintf("Containerd found!\n")
		systemEnvironment.containerdInstalled = true
	}

	// Check runc
	_, err = exec.LookPath("runc")
	if err != nil {
		WarnPrintf("runc not found! runc(version %s) will be automatically installed!\n", systemEnvironment.runcVersion)
	} else {
		SuccessPrintf("runc found!\n")
		systemEnvironment.runcInstalled = true
	}

	// Check CNI plugins
	_, err = os.Stat("/opt/cni/bin")
	if err != nil {
		WarnPrintf("CNI plugins not found! CNI plugins(version %s) will be automatically installed!\n", systemEnvironment.cniPluginsVersion)
	} else {
		SuccessPrintf("CNI plugins found!\n")
		systemEnvironment.cniPluginsInstalled = true
	}

	// Add OS-specific dependencies to installation lists
	switch currentOS {
	case "ubuntu":
		systemEnvironment.dependencies = "git wget curl build-essential apt-transport-https ca-certificates"
	case "rocky linux":
		systemEnvironment.dependencies = ""
	case "centos":
		systemEnvironment.dependencies = ""
	default:
		FatalPrintf("Unsupported Linux distribution: %s\n", currentOS)
	}

	SuccessPrintf("Finish checking system environment!\n")
}

// Initialize system environment
func SystemInit() {

	// Initialize
	var err error
	CheckSystemEnvironment()
	CreateTmpDir()
	defer CleanUpTmpDir()

	// Turn off unattended-upgrades on ubuntu
	WaitPrintf("Turning off automatic upgrade")
	_, err = TurnOffAutomaticUpgrade()
	CheckErrorWithTagAndMsg(err, "Failed to turn off automatic upgrade!\n")

	// Disable swap
	WaitPrintf("Disabling swap")
	_, err = ExecShellCmd("sudo swapoff -a && sudo cp /etc/fstab /etc/fstab.old") // Turn off Swap && Backup fstab file
	CheckErrorWithTagAndMsg(err, "Failed to disable swap!\n")

	WaitPrintf("Modifying fstab")
	// Modify fstab to disable swap permanently
	_, err = ExecShellCmd("sudo sed -i 's/#\\s*\\(.*swap.*\\)/\\1/g' /etc/fstab && sudo sed -i 's/.*swap.*/# &/g' /etc/fstab")
	CheckErrorWithTagAndMsg(err, "Failed to dodify fstab!\n")

	// Install dependencies
	WaitPrintf("Installing dependencies")
	err = InstallPackages(systemEnvironment.dependencies)
	CheckErrorWithTagAndMsg(err, "Failed to install dependencies!\n")

	// Install Golang
	if !systemEnvironment.goInstalled {
		// Download & Extract Golang
		WaitPrintf("Downloading Golang(ver %s)", systemEnvironment.goVersion)
		filePathName, err := DownloadToTmpDir(systemEnvironment.goDownloadUrlTemplate, systemEnvironment.goVersion, currentArch)
		CheckErrorWithTagAndMsg(err, "Failed to download Golang(ver %s)!\n", systemEnvironment.goVersion)
		WaitPrintf("Extracting Golang")
		_, err = ExecShellCmd("sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf %s", filePathName)
		CheckErrorWithTagAndMsg(err, "Failed to extract Golang!\n")

		// For bash
		_, err = ExecShellCmd("echo 'export PATH=$PATH:/usr/local/go/bin' >> %s/.bashrc", userHomeDir)
		CheckErrorWithMsg(err, "Failed to update PATH!\n")
		// For zsh
		_, err = exec.LookPath("zsh")
		if err != nil {
			_, err = ExecShellCmd("echo 'export PATH=$PATH:/usr/local/go/bin' >> %s/.zshrc", userHomeDir)
			CheckErrorWithMsg(err, "Failed to update PATH!\n")
		}
	}

	// Install containerd
	if !systemEnvironment.containerdInstalled {
		// Download containerd
		WaitPrintf("Downloading containerd(ver %s)", systemEnvironment.containerdVersion)
		filePathName, err := DownloadToTmpDir(
			systemEnvironment.containerdDownloadUrlTemplate,
			systemEnvironment.containerdVersion,
			systemEnvironment.containerdVersion,
			currentArch)
		CheckErrorWithTagAndMsg(err, "Failed to Download containerd(ver %s)\n", systemEnvironment.containerdVersion)
		// Extract containerd
		WaitPrintf("Extracting containerd")
		_, err = ExecShellCmd("sudo tar Cxzvf /usr/local %s", filePathName)
		CheckErrorWithTagAndMsg(err, "Failed to extract containerd!\n")
		// Start containerd via systemd
		WaitPrintf("Downloading systemd profile for containerd")
		filePathName, err = DownloadToTmpDir(systemEnvironment.containerdSystemdProfileDownloadUrl)
		CheckErrorWithTagAndMsg(err, "Failed to download systemd profile for containerd!\n")
		WaitPrintf("Starting containerd via systemd")
		_, err = ExecShellCmd("sudo cp %s /lib/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now containerd", filePathName)
		CheckErrorWithTagAndMsg(err, "Failed to start containerd via systemd!\n")
	}

	// Install runc
	if !systemEnvironment.runcInstalled {
		// Download runc
		WaitPrintf("Downloading runc(ver %s)", systemEnvironment.runcVersion)
		filePathName, err := DownloadToTmpDir(
			systemEnvironment.runcDownloadUrlTemplate,
			systemEnvironment.runcVersion,
			currentArch)
		CheckErrorWithTagAndMsg(err, "Failed to download runc(ver %s)!\n", systemEnvironment.runcVersion)
		// Install runc
		WaitPrintf("Installing runc")
		_, err = ExecShellCmd("sudo install -m 755 %s /usr/local/sbin/runc", filePathName)
		CheckErrorWithTagAndMsg(err, "Failed to install runc!\n")
	}

	// Install CNI plugins
	if !systemEnvironment.cniPluginsInstalled {
		WaitPrintf("Downloading CNI plugins(ver %s)", systemEnvironment.cniPluginsVersion)
		filePathName, err := DownloadToTmpDir(
			systemEnvironment.cniPluginsDownloadUrlTemplate,
			systemEnvironment.cniPluginsVersion,
			currentArch,
			systemEnvironment.cniPluginsVersion)
		CheckErrorWithTagAndMsg(err, "Failed to download CNI plugins(ver %s)!\n", systemEnvironment.cniPluginsVersion)
		WaitPrintf("Extracting CNI plugins")
		_, err = ExecShellCmd("sudo mkdir -p /opt/cni/bin && sudo tar Cxzvf /opt/cni/bin %s", filePathName)
		CheckErrorWithTagAndMsg(err, "Failed to extract CNI plugins!\n")
	}

	// Configure the systemd cgroup driver
	WaitPrintf("Configuring the systemd cgroup driver")
	_, err = ExecShellCmd(
		"containerd config default > %s && sudo mkdir -p /etc/containerd && sudo cp %s /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml && sudo systemctl restart containerd",
		systemEnvironment.tmpDir+"/config.toml",
		systemEnvironment.tmpDir+"/config.toml")
	CheckErrorWithTagAndMsg(err, "Failed to configure the systemd cgroup driver!\n")

	// Enable IP forwading & br_netfilter
	WaitPrintf("Enabling IP forwading & br_netfilter")
	_, err = ExecShellCmd("sudo modprobe br_netfilter && sudo sysctl -w net.ipv4.ip_forward=1")
	CheckErrorWithTagAndMsg(err, "Failed to enable IP forwading & br_netfilter!\n")
	// Ensure Boot-Resistant
	WaitPrintf("Ensuring Boot-Resistant")
	_, err = ExecShellCmd("echo 'br_netfilter' | sudo tee /etc/modules-load.d/netfilter.conf && sudo sed -i 's/# *net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && sudo sed -i 's/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/g' /etc/sysctl.conf")
	CheckErrorWithTagAndMsg(err, "Failed to ensure Boot-Resistant!\n")

	// Install kubeadm, kubelet, kubectl
	switch currentOS {
	case "ubuntu":
		// Download Google Cloud public signing key and Add the Kubernetes apt repository
		WaitPrintf("Adding the Kubernetes apt repository")
		_, err = ExecShellCmd("sudo mkdir -p /etc/apt/keyrings && sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list")
		CheckErrorWithTagAndMsg(err, "Failed to add the Kubernetes apt repository!\n")
		// Install kubeadm, kubelet, kubectl via apt
		WaitPrintf("Installing kubeadm, kubelet, kubectl")
		err = InstallPackages("kubeadm=%s kubelet=%s kubectl=%s", systemEnvironment.kubeadmVersion, systemEnvironment.kubeletVersion, systemEnvironment.kubectlVersion)
		CheckErrorWithTagAndMsg(err, "Failed to install kubeadm, kubelet, kubectl!\n")
		// Lock kubeadm, kubelet, kubectl version
		WaitPrintf("Locking kubeadm, kubelet, kubectl version")
		_, err = ExecShellCmd("sudo apt-mark hold kubelet kubeadm kubectl")
		CheckErrorWithTagAndMsg(err, "Failed to lock kubeadm, kubelet, kubectl version!\n")
	default:
		FatalPrintf("Unsupported Linux distribution: %s\n", currentOS)
	}

}
