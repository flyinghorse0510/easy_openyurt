package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

type KubeConfig struct {
	k8sVersion                string
	alternativeImageRepo      string
	apiserverAdvertiseAddress string
	podNetworkCidr            string
	apiserverPort             string
	apiserverToken            string
	apiserverTokenHash        string
}

var kubeConfig = KubeConfig{
	k8sVersion:                "1.23.16",
	alternativeImageRepo:      "",
	apiserverAdvertiseAddress: "",
	podNetworkCidr:            "10.244.0.0/16",
	apiserverPort:             "6443",
	apiserverToken:            "",
	apiserverTokenHash:        "",
}

// Parse parameters for subcommand `kube`
func ParseSubcommandKube(args []string) {
	nodeRole := args[0]
	operation := args[1]
	var help bool
	// Add parameters to flag set
	kubeFlagsName := fmt.Sprintf("%s kube %s %s", os.Args[0], nodeRole, operation)
	kubeFlags := flag.NewFlagSet(kubeFlagsName, flag.ExitOnError)
	kubeFlags.BoolVar(&help, "help", false, "Show help")
	kubeFlags.BoolVar(&help, "h", false, "Show help")
	switch nodeRole {
	case "master":
		// Parse parameters for `kube master init`
		if operation != "init" {
			InfoPrintf("Usage: %s %s %s init [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
		kubeFlags.StringVar(&kubeConfig.k8sVersion, "k8s-version", kubeConfig.k8sVersion, "Kubernetes version")
		kubeFlags.StringVar(&kubeConfig.alternativeImageRepo, "alternative-image-repo", kubeConfig.alternativeImageRepo, "Alternative image repository")
		kubeFlags.StringVar(&kubeConfig.apiserverAdvertiseAddress, "apiserver-advertise-address", kubeConfig.apiserverAdvertiseAddress, "Kubernetes API server advertise address")
		kubeFlags.Parse(args[2:])
		// Show help
		if help {
			kubeFlags.Usage()
			os.Exit(0)
		}
		kube_master_init()
		SuccessPrintf("Master node key information has been written to %s/masterKey.yaml! Check for details.\n", currentDir)
	case "worker":
		// Parse parameters for `kube worker join`
		if operation != "join" {
			InfoPrintf("Usage: %s %s %s join [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
		kubeFlags.StringVar(&kubeConfig.apiserverAdvertiseAddress, "apiserver-advertise-address", kubeConfig.apiserverAdvertiseAddress, "Kubernetes API server advertise address (**REQUIRED**)")
		kubeFlags.StringVar(&kubeConfig.apiserverPort, "apiserver-port", kubeConfig.apiserverPort, "Kubernetes API server port")
		kubeFlags.StringVar(&kubeConfig.apiserverToken, "apiserver-token", kubeConfig.apiserverToken, "Kubernetes API server token (**REQUIRED**)")
		kubeFlags.StringVar(&kubeConfig.apiserverTokenHash, "apiserver-token-hash", kubeConfig.apiserverTokenHash, "Kubernetes API server token hash (**REQUIRED**)")
		kubeFlags.Parse(args[2:])
		// Show help
		if help {
			kubeFlags.Usage()
			os.Exit(0)
		}
		// Check required parameters
		if len(kubeConfig.apiserverAdvertiseAddress) == 0 {
			kubeFlags.Usage()
			FatalPrintf("Parameter --apiserver-advertise-address needed!\n")
		}
		if len(kubeConfig.apiserverToken) == 0 {
			kubeFlags.Usage()
			FatalPrintf("Parameter --apiserver-token needed!\n")
		}
		if len(kubeConfig.apiserverTokenHash) == 0 {
			kubeFlags.Usage()
			FatalPrintf("Parameter --apiserver-token-hash needed!\n")
		}
		kube_worker_join()
		SuccessPrintf("Successfully joined Kubernetes cluster!\n")
	default:
		InfoPrintf("Usage: %s %s <master | worker> <init | join> [parameters...]\n", os.Args[0], os.Args[1])
		FatalPrintf("Invalid nodeRole: <nodeRole> -> %s\n", nodeRole)
	}
}

// Initialize the master node of Kubernetes cluster
func kube_master_init() {

	// Initialize
	var err error
	check_kube_environment()
	CreateTmpDir()
	defer CleanUpTmpDir()

	// Pre-pull Image
	WaitPrintf("Pre-Pulling required images")
	shellCmd := fmt.Sprintf("sudo kubeadm config images pull --kubernetes-version %s ", kubeConfig.k8sVersion)
	if len(kubeConfig.alternativeImageRepo) > 0 {
		shellCmd = fmt.Sprintf(shellCmd+"--image-repository %s ", kubeConfig.alternativeImageRepo)
	}
	_, err = ExecShellCmd(shellCmd)
	CheckErrorWithTagAndMsg(err, "Failed to pre-pull required images!\n")

	// Deploy Kubernetes
	WaitPrintf("Deploying Kubernetes(version %s)", kubeConfig.k8sVersion)
	shellCmd = fmt.Sprintf("sudo kubeadm init --kubernetes-version %s --pod-network-cidr=\"%s\" ", kubeConfig.k8sVersion, kubeConfig.podNetworkCidr)
	if len(kubeConfig.alternativeImageRepo) > 0 {
		shellCmd = fmt.Sprintf(shellCmd+"--image-repository %s ", kubeConfig.alternativeImageRepo)
	}
	if len(kubeConfig.apiserverAdvertiseAddress) > 0 {
		shellCmd = fmt.Sprintf(shellCmd+"--apiserver-advertise-address=%s ", kubeConfig.apiserverAdvertiseAddress)
	}
	shellCmd = fmt.Sprintf(shellCmd+"| tee %s/masterNodeInfo", systemEnvironment.tmpDir)
	_, err = ExecShellCmd(shellCmd)
	CheckErrorWithTagAndMsg(err, "Failed to deploy Kubernetes(version %s)!\n", kubeConfig.k8sVersion)

	// Make kubectl work for non-root user
	WaitPrintf("Making kubectl work for non-root user")
	_, err = ExecShellCmd("mkdir -p %s/.kube && sudo cp -i /etc/kubernetes/admin.conf %s/.kube/config && sudo chown $(id -u):$(id -g) %s/.kube/config",
		userHomeDir,
		userHomeDir,
		userHomeDir)
	CheckErrorWithTagAndMsg(err, "Failed to make kubectl work for non-root user!\n")

	// Install Pod Network
	WaitPrintf("Installing pod network")
	_, err = ExecShellCmd("kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml")
	CheckErrorWithTagAndMsg(err, "Failed to install pod network!\n")

	// Extract master node information from logs
	WaitPrintf("Extracting master node information from logs")
	shellOut, err := ExecShellCmd("sed -n '/.*kubeadm join.*/p' < %s/masterNodeInfo | sed -n 's/.*join \\(.*\\):\\(\\S*\\) --token \\(\\S*\\).*/\\1 \\2 \\3/p'", systemEnvironment.tmpDir)
	CheckErrorWithMsg(err, "Failed to extract master node information from logs!\n")
	splittedOut := strings.Split(shellOut, " ")
	kubeConfig.apiserverAdvertiseAddress = splittedOut[0]
	kubeConfig.apiserverPort = splittedOut[1]
	kubeConfig.apiserverToken = splittedOut[2]
	shellOut, err = ExecShellCmd("sed -n '/.*sha256:.*/p' < %s/masterNodeInfo | sed -n 's/.*\\(sha256:\\S*\\).*/\\1/p'", systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to extract master node information from logs!\n")
	kubeConfig.apiserverTokenHash = shellOut
	masterKeyYamlTemplate := `apiserverAdvertiseAddress: %s
apiserverPort: %s
apiserverToken: %s
apiserverTokenHash: %s`

	// Create masterKey.yaml with master node information
	WaitPrintf("Creating masterKey.yaml with master node information")
	masterKeyYamlFile, err := os.OpenFile(currentDir+"/masterKey.yaml", os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0666)
	CheckErrorWithMsg(err, "Failed to create masterKey.yaml with master node information!\n")
	defer masterKeyYamlFile.Close()
	masterKeyYaml := fmt.Sprintf(
		masterKeyYamlTemplate,
		kubeConfig.apiserverAdvertiseAddress,
		kubeConfig.apiserverPort,
		kubeConfig.apiserverToken,
		kubeConfig.apiserverTokenHash)
	_, err = masterKeyYamlFile.WriteString(masterKeyYaml)
	CheckErrorWithTagAndMsg(err, "Failed to create masterKey.yaml with master node information!\n")

}

// Join worker node to Kubernetes cluster
func kube_worker_join() {

	// Initialize
	var err error

	// Join Kubernetes cluster
	WaitPrintf("Joining Kubernetes cluster")
	_, err = ExecShellCmd("sudo kubeadm join %s:%s --token %s --discovery-token-ca-cert-hash %s", kubeConfig.apiserverAdvertiseAddress, kubeConfig.apiserverPort, kubeConfig.apiserverToken, kubeConfig.apiserverTokenHash)
	CheckErrorWithTagAndMsg(err, "Failed to join Kubernetes cluster!\n")
}

func check_kube_environment() {
	// Temporarily unused
}
