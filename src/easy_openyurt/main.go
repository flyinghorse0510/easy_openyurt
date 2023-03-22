// Author: Haoyuan Ma <flyinghorse0510@zju.edu.cn>
package main

import (
	"os"
)

var _version = "0.2.0b"

// Init
func init() {
	PrintWelcomeInfo()
	PrintWarningInfo()
	DetectOS()
	DetectArch()
	GetCurrentDir()
	GetUserHomeDir()
	CreateLogs()
}

func main() {
	// Check Arguments number
	argc := len(os.Args)
	if argc < 4 {
		PrintGeneralUsage()
		FatalPrintf("Invalid arguments: too few arguments!\n")
	}
	// Parse subcommand
	operationObject := os.Args[1]
	switch operationObject {
	case "system":
		// `system` subcommand
		ParseSubcommandSystem(os.Args[2:])
	case "kube":
		// `kube` subcommand
		ParseSubcommandKube(os.Args[2:])
	case "yurt":
		// `yurt` subcommand
		ParseSubcommandYurt(os.Args[2:])
	default:
		PrintGeneralUsage()
		FatalPrintf("Invalid object: <object> -> %s\n", operationObject)
	}
}
