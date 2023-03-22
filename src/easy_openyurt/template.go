// Author: Haoyuan Ma <flyinghorse0510@zju.edu.cn>
package main

const (
	yurthubTemplate = `apiVersion: v1
kind: Pod
metadata:
  labels:
    k8s-app: yurt-hub
  name: yurt-hub
  namespace: kube-system
spec:
  volumes:
  - name: hub-dir
    hostPath:
      path: /var/lib/yurthub
      type: DirectoryOrCreate
  - name: kubernetes
    hostPath:
      path: /etc/kubernetes
      type: Directory
  - name: pem-dir
    hostPath:
      path: /var/lib/kubelet/pki
      type: Directory
  containers:
  - name: yurt-hub
    image: openyurt/yurthub:latest
    imagePullPolicy: IfNotPresent
    volumeMounts:
    - name: hub-dir
      mountPath: /var/lib/yurthub
    - name: kubernetes
      mountPath: /etc/kubernetes
    - name: pem-dir
      mountPath: /var/lib/kubelet/pki
    command:
    - yurthub
    - --v=2
    - --server-addr=https://__kubernetes_master_address__
    - --node-name=$(NODE_NAME)
    - --join-token=__bootstrap_token__
    livenessProbe:
      httpGet:
        host: 127.0.0.1
        path: /v1/healthz
        port: 10267
      initialDelaySeconds: 300
      periodSeconds: 5
      failureThreshold: 3
    resources:
      requests:
        cpu: 150m
        memory: 150Mi
      limits:
        memory: 300Mi
    securityContext:
      capabilities:
        add: ["NET_ADMIN", "NET_RAW"]
    env:
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
  hostNetwork: true
  priorityClassName: system-node-critical
  priority: 2000001000`

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

	restartPodsShellTemplate = `existingPods=$(kubectl get pod -A -o wide | grep %s)
originalIFS=${IFS}
IFS=$'\n'
while read -r pod
do
	if [ -z "$(echo ${pod} | sed -n "/.*yurt-hub.*/p")" ]; then
		podNameSpace=$(echo ${pod} | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\1/p")
		podName=$(echo ${pod} | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\2/p")
		echo "${podNameSpace} ${podName}"
	fi
done <<< ${existingPods}
IFS=${originalIFS}`
)
