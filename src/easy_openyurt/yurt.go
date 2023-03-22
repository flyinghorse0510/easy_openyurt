// Author: Haoyuan Ma <flyinghorse0510@zju.edu.cn>
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

type YurtEnvironment struct {
	helmInstalled                   bool
	helmPublicSigningKeyDownloadUrl string
	kustomizeInstalled              bool
	kustomizeScriptDownloadUrl      string
	masterAsCloud                   bool
	workerNodeName                  string
	workerAsEdge                    bool
	dependencies                    string
}

var yurtEnvironment = YurtEnvironment{
	helmInstalled:                   false,
	helmPublicSigningKeyDownloadUrl: "https://baltocdn.com/helm/signing.asc",
	kustomizeInstalled:              false,
	kustomizeScriptDownloadUrl:      "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh",
	masterAsCloud:                   true,
	workerNodeName:                  "",
	workerAsEdge:                    true,
	dependencies:                    "",
}

// Parse parameters for subcommand `yurt`
func ParseSubcommandYurt(args []string) {
	nodeRole := args[0]
	operation := args[1]
	var help bool
	// Add parameters to flag set
	yurtFlagsName := fmt.Sprintf("%s yurt %s %s", os.Args[0], nodeRole, operation)
	yurtFlags := flag.NewFlagSet(yurtFlagsName, flag.ExitOnError)
	yurtFlags.BoolVar(&help, "help", false, "Show help")
	yurtFlags.BoolVar(&help, "h", false, "Show help")
	switch nodeRole {
	case "master":
		// Parse parameters for `yurt master init`
		if operation == "init" {
			yurtFlags.BoolVar(&yurtEnvironment.masterAsCloud, "master-as-cloud", yurtEnvironment.masterAsCloud, "Treat master as cloud node")
			yurtFlags.Parse(args[2:])
			// Show help
			if help {
				yurtFlags.Usage()
				os.Exit(0)
			}
			YurtMasterInit()
			SuccessPrintf("Successfully init OpenYurt cluster master node!\n")
		} else if operation == "expand" {
			// Parse parameters for `yurt master expand`
			yurtFlags.BoolVar(&yurtEnvironment.workerAsEdge, "worker-as-edge", yurtEnvironment.workerAsEdge, "Treat worker as edge node")
			yurtFlags.StringVar(&yurtEnvironment.workerNodeName, "worker-node-name", yurtEnvironment.workerNodeName, "Worker node name(**REQUIRED**)")
			yurtFlags.Parse(args[2:])
			// Show help
			if help {
				yurtFlags.Usage()
				os.Exit(0)
			}
			// Check required parameters
			if len(yurtEnvironment.workerNodeName) == 0 {
				yurtFlags.Usage()
				FatalPrintf("Parameter --worker-node-name needed!\n")
			}
			YurtMasterExpand()
			SuccessPrintf("Successfully expand OpenYurt to node [%s]!\n", yurtEnvironment.workerNodeName)
		} else {
			InfoPrintf("Usage: %s %s %s <init | expand> [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
	case "worker":
		// Parse parameters for `yurt worker join`
		if operation != "join" {
			InfoPrintf("Usage: %s %s %s join [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
		yurtFlags.StringVar(&kubeConfig.apiserverAdvertiseAddress, "apiserver-advertise-address", kubeConfig.apiserverAdvertiseAddress, "Kubernetes API server advertise address (**REQUIRED**)")
		yurtFlags.StringVar(&kubeConfig.apiserverPort, "apiserver-port", kubeConfig.apiserverPort, "Kubernetes API server port")
		yurtFlags.StringVar(&kubeConfig.apiserverToken, "apiserver-token", kubeConfig.apiserverToken, "Kubernetes API server token (**REQUIRED**)")
		yurtFlags.Parse(args[2:])
		// Show help
		if help {
			yurtFlags.Usage()
			os.Exit(0)
		}
		// Check required parameters
		if len(kubeConfig.apiserverAdvertiseAddress) == 0 {
			yurtFlags.Usage()
			FatalPrintf("Parameter --apiserver-advertise-address needed!\n")
		}
		if len(kubeConfig.apiserverToken) == 0 {
			yurtFlags.Usage()
			FatalPrintf("Parameter --apiserver-token needed!\n")
		}
		YurtWorkerJoin()
		SuccessPrintf("Successfully joined OpenYurt cluster!\n")
	default:
		InfoPrintf("Usage: %s %s <master | worker> <init | join | expand> [parameters...]\n", os.Args[0], os.Args[1])
		FatalPrintf("Invalid nodeRole: <nodeRole> -> %s\n", nodeRole)
	}
}

func CheckYurtMasterEnvironment() {

	// Check environment
	var err error
	InfoPrintf("Checking system environment...\n")

	// Check Helm
	_, err = exec.LookPath("helm")
	if err != nil {
		WarnPrintf("Helm not found! Helm will be automatically installed!\n")
	} else {
		SuccessPrintf("Helm found!\n")
		yurtEnvironment.helmInstalled = true
	}

	// Check Kustomize
	_, err = exec.LookPath("kustomize")
	if err != nil {
		WarnPrintf("Kustomize not found! Kustomize will be automatically installed!\n")
	} else {
		SuccessPrintf("Kustomize found!\n")
		yurtEnvironment.kustomizeInstalled = true
	}

	// Add OS-specific dependencies to installation lists
	switch currentOS {
	case "ubuntu":
		yurtEnvironment.dependencies = "curl apt-transport-https ca-certificates build-essential git"
	case "rocky linux":
		yurtEnvironment.dependencies = ""
	case "centos":
		yurtEnvironment.dependencies = ""
	default:
		FatalPrintf("Unsupported OS: %s\n", currentOS)
	}

	SuccessPrintf("Finished checking system environment!\n")
}

// Initialize Openyurt on master node
func YurtMasterInit() {
	// Initialize
	var err error
	CheckYurtMasterEnvironment()
	CreateTmpDir()
	defer CleanUpTmpDir()

	// Install dependencies
	WaitPrintf("Installing dependencies")
	err = InstallPackages(yurtEnvironment.dependencies)
	CheckErrorWithTagAndMsg(err, "Failed to install dependencies!\n")

	// Treat master as cloud node
	if yurtEnvironment.masterAsCloud {
		WarnPrintf("Master node WILL also be treated as a cloud node!\n")
		ExecShellCmd("kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-")
		ExecShellCmd("kubectl taint nodes --all node-role.kubernetes.io/control-plane-")
	}

	// Install helm
	if !yurtEnvironment.helmInstalled {
		switch currentOS {
		case "ubuntu":
			// Download public signing key && Add the Helm apt repository
			WaitPrintf("Downloading public signing key && Add the Helm apt repository")
			// Download public signing key
			filePathName, err := DownloadToTmpDir(yurtEnvironment.helmPublicSigningKeyDownloadUrl)
			CheckErrorWithMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			_, err = ExecShellCmd("sudo mkdir -p /usr/share/keyrings && cat %s | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null", filePathName)
			CheckErrorWithMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			// Add the Helm apt repository
			_, err = ExecShellCmd(`echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list`)
			CheckErrorWithTagAndMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			// Install helm
			WaitPrintf("Installing Helm")
			err = InstallPackages("helm")
			CheckErrorWithTagAndMsg(err, "Failed to install helm!\n")
		default:
			FatalPrintf("Unsupported Linux distribution: %s\n", currentOS)
		}
	}

	if !yurtEnvironment.kustomizeInstalled {
		// Download kustomize helper script
		WaitPrintf("Downloading kustomize")
		filePathName, err := DownloadToTmpDir(yurtEnvironment.kustomizeScriptDownloadUrl)
		CheckErrorWithMsg(err, "Failed to download kustomize!\n")
		// Download kustomize
		_, err = ExecShellCmd("chmod u+x %s && %s %s", filePathName, filePathName, systemEnvironment.tmpDir)
		CheckErrorWithTagAndMsg(err, "Failed to download kustomize!\n")
		// Install kustomize
		WaitPrintf("Installing kustomize")
		_, err = ExecShellCmd("sudo cp %s /usr/local/bin", systemEnvironment.tmpDir+"/kustomize")
		CheckErrorWithTagAndMsg(err, "Failed to Install kustomize!\n")
	}

	// Add OpenYurt repo with helm
	WaitPrintf("Adding OpenYurt repo with helm")
	_, err = ExecShellCmd("helm repo add openyurt https://openyurtio.github.io/openyurt-helm")
	CheckErrorWithTagAndMsg(err, "Failed to add OpenYurt repo with helm!\n")

	// Deploy yurt-app-manager
	WaitPrintf("Deploying yurt-app-manager")
	_, err = ExecShellCmd("helm upgrade --install yurt-app-manager -n kube-system openyurt/yurt-app-manager")
	CheckErrorWithTagAndMsg(err, "Failed to deploy yurt-app-manager!\n")

	// Wait for yurt-app-manager to be ready
	WaitPrintf("Waiting for yurt-app-manager to be ready")
	waitCount := 1
	for {
		yurtAppManagerStatus, err := ExecShellCmd(`kubectl get pod -n kube-system | grep yurt-app-manager | sed -n "s/\s*\(\S*\)\s*\(\S*\)\s*\(\S*\).*/\2 \3/p"`)
		CheckErrorWithMsg(err, "Failed to wait for yurt-app-manager to be ready!\n")
		if yurtAppManagerStatus == "1/1 Running" {
			SuccessPrintf("\n")
			break
		} else {
			WarnPrintf("Waiting for yurt-app-manager to be ready [%ds]\n", waitCount)
			waitCount += 1
			time.Sleep(time.Second)
		}
	}

	// Deploy yurt-controller-manager
	WaitPrintf("Deploying yurt-controller-manager")
	_, err = ExecShellCmd("helm upgrade --install openyurt -n kube-system openyurt/openyurt")
	CheckErrorWithTagAndMsg(err, "Failed to deploy yurt-controller-manager!\n")

	// Setup raven-controller-manager Component
	// Clone repository
	WaitPrintf("Cloning repo: raven-controller-manager")
	_, err = ExecShellCmd("git clone --quiet https://github.com/openyurtio/raven-controller-manager.git %s/raven-controller-manager", systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to clone repo: raven-controller-manager!\n")
	// Deploy raven-controller-manager
	WaitPrintf("Deploying raven-controller-manager")
	_, err = ExecShellCmd("pushd %s/raven-controller-manager && git checkout v0.3.0 && make generate-deploy-yaml && kubectl apply -f _output/yamls/raven-controller-manager.yaml && popd", systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to deploy raven-controller-manager!\n")

	// Setup raven-agent Component
	// Clone repository
	WaitPrintf("Cloning repo: raven-agent")
	_, err = ExecShellCmd("git clone --quiet https://github.com/openyurtio/raven.git %s/raven-agent", systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to clone repo: raven-agent!\n")
	// Deploy raven-agent
	WaitPrintf("Deploying raven-agent")
	_, err = ExecShellCmd("pushd %s/raven-agent && git checkout v0.3.0 && FORWARD_NODE_IP=true make deploy && popd", systemEnvironment.tmpDir)
	CheckErrorWithTagAndMsg(err, "Failed to deploy raven-agent!\n")
}

// Expand Openyurt to worker node
func YurtMasterExpand() {
	// Initialize
	var err error
	var workerAsEdge string

	// Label worker node as cloud/edge
	WaitPrintf("Labeling worker node: %s", yurtEnvironment.workerNodeName)
	if yurtEnvironment.workerAsEdge {
		workerAsEdge = "true"
	} else {
		workerAsEdge = "false"
	}
	_, err = ExecShellCmd("kubectl label node %s openyurt.io/is-edge-worker=%s --overwrite", yurtEnvironment.workerNodeName, workerAsEdge)
	CheckErrorWithTagAndMsg(err, "Failed to label worker node!\n")

	// Activate the node autonomous mode
	WaitPrintf("Activating the node autonomous mode")
	_, err = ExecShellCmd("kubectl annotate node %s node.beta.openyurt.io/autonomy=true --overwrite", yurtEnvironment.workerNodeName)
	CheckErrorWithTagAndMsg(err, "Failed to activate the node autonomous mode!\n")

	// Wait for worker node to be Ready
	WaitPrintf("Waiting for worker node to be ready")
	waitCount := 1
	for {
		workerNodeStatus, err := ExecShellCmd(`kubectl get nodes | sed -n "/.*%s.*/p" | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\2/p"`, yurtEnvironment.workerNodeName)
		CheckErrorWithMsg(err, "Failed to wait for worker node to be ready!\n")
		if workerNodeStatus == "Ready" {
			SuccessPrintf("\n")
			break
		} else {
			WarnPrintf("Waiting for worker node to be ready [%ds]\n", waitCount)
			waitCount += 1
			time.Sleep(time.Second)
		}
	}

	// Restart pods in the worker node
	WaitPrintf("Restarting pods in the worker node")
	shellOutput, err := ExecShellCmd(restartPodsShellTemplate, yurtEnvironment.workerNodeName)
	CheckErrorWithMsg(err, "Failed to restart pods in the worker node!\n")
	podsToBeRestarted := strings.Split(shellOutput, "\n")
	for _, pods := range podsToBeRestarted {
		podsInfo := strings.Split(pods, " ")
		WaitPrintf("Restarting pod: %s => %s\n", podsInfo[0], podsInfo[1])
		_, err = ExecShellCmd("kubectl -n %s delete pod %s", podsInfo[0], podsInfo[1])
		CheckErrorWithTagAndMsg(err, "Failed to restart pods in the worker node!\n")
	}
}

// Join existing Kubernetes worker node to Openyurt cluster
func YurtWorkerJoin() {

	// Initialize
	var err error

	// Set up Yurthub
	WaitPrintf("Setting up Yurthub")
	_, err = ExecShellCmd(
		"echo '%s' | sed -e 's|__kubernetes_master_address__|%s:%s|' -e 's|__bootstrap_token__|%s|' | sudo tee /etc/kubernetes/manifests/yurthub-ack.yaml",
		yurthubTemplate,
		kubeConfig.apiserverAdvertiseAddress,
		kubeConfig.apiserverPort,
		kubeConfig.apiserverToken)
	CheckErrorWithTagAndMsg(err, "Failed to set up Yurthub!\n")

	// Configure Kubelet
	WaitPrintf("Configuring kubelet")
	ExecShellCmd("sudo mkdir -p /var/lib/openyurt && echo '%s' | sudo tee /var/lib/openyurt/kubelet.conf", kubeletTemplate)
	CheckErrorWithMsg(err, "Failed to configure kubelet!\n")
	ExecShellCmd(`sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf\ --kubeconfig=\/etc\/kubernetes\/kubelet.conf|KUBELET_KUBECONFIG_ARGS=--kubeconfig=\/var\/lib\/openyurt\/kubelet.conf|g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf`)
	CheckErrorWithMsg(err, "Failed to configure kubelet!\n")
	ExecShellCmd("sudo systemctl daemon-reload && sudo systemctl restart kubelet")
	CheckErrorWithTagAndMsg(err, "Failed to configure kubelet!\n")
}
