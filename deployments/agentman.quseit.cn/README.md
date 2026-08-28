# 查看证书步骤

# 查看所有 TLS Secret
kubectl get secret -n clawmanager-system | grep -E 'tls|ssl|ingress'

# 查看特定 Secret 的详细信息
kubectl describe secret <secret-name> -n clawmanager-system


## 实际执行
kubectl describe secret agentman-tls -n clawmanager-system 
