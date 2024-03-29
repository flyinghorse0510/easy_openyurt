package template

const (
	kubeletTemplate = `apiVersion: v1
clusters:
- cluster:
    server: http://127.0.0.1:10261
  name: default-cluster
contexts:
- context:
    cluster: default-cluster
    namespace: default
    user: default-auth
  name: default-context
current-context: default-context
kind: Config
preferences: {}`
)

func GetKubeletConfig() string {
	return kubeletTemplate
}

func GetNetworkAddonConfigURL() string {
	return vHiveConfigsURL + "/calico/canal.yaml"
}
