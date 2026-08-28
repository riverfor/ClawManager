kubectl patch ingress clawmanager -n clawmanager-system --type=json -p='[{"op": "replace", "path": "/spec/rules/0/host", "value": "agentman.quseit.cn"}]'

kubectl patch svc traefik -n kube-system --type=json -p='[
  {"op": "add", "path": "/spec/externalIPs", "value": ["82.157.175.119"]}
]'
