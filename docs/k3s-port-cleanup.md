# K3s 残留进程与端口占用清理指南

## 问题现象

在停止 k3s 服务后，端口 80/443 仍被"占用"，无法被其他服务绑定。

## 根本原因

k3s 停止后存在两类残留：

1. **containerd-shim 残留进程** — k3s 服务停止时，其启动的 containerd-shim 子进程未随主进程退出，仍留在后台运行。
2. **iptables/nftables NAT 规则残留** — k3s 的 CNI 网络插件（如 flannel）在运行时会向 iptables 的 `nat` 表注入大量 DNAT 规则，将宿主机的 80/443 端口流量转发到集群内 Pod。k3s 停止后这些规则不会自动清除。

典型的残留 NAT 规则示例：

```
# 80 端口 → CNI hostport Pod
DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:80  to:10.42.0.187:80

# 443 端口 → clawmanager-frontend
DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:443  to:10.42.0.16:8443

# traefik web/websecure
DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:80  to:10.42.0.15:8000   (kube-system/traefik:web)
DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:443  to:10.42.0.15:8443  (kube-system/traefik:websecure)
```

这些规则导致外部流量到达 80/443 时被 DNAT 到已不存在的 Pod，表现为"端口被占用/不可用"。

## 诊断方法

```bash
# 检查是否有进程在监听 80/443
sudo ss -tlnp | grep -E ':443|:80'

# 检查 k3s 残留进程
sudo systemctl status k3s

# 检查 iptables NAT 规则中与 80/443 相关的条目
sudo iptables -t nat -L -n | grep -E 'dpt:80|dpt:443'

# 检查 nftables 规则
sudo nft list ruleset | grep -E '443|80'
```

## 清理方案

### 方案一：使用 k3s 自带脚本（推荐）

`k3s-killall.sh` 会完整清理所有残留（进程 + 网络规则 + 挂载点），且不会删除集群数据，后续可正常重启 k3s。

```bash
/usr/local/bin/k3s-killall.sh
```

### 方案二：手动清理

如果 `k3s-killall.sh` 不存在或执行失败，可按以下步骤手动清理：

```bash
# 1. 杀掉所有残留的 containerd-shim 进程
sudo pkill -f 'containerd-shim.*k8s.io'

# 2. 清理 iptables NAT 规则
sudo iptables -t nat -F CNI-HOSTPORT-DNAT 2>/dev/null
sudo iptables -t nat -F KUBE-SERVICES 2>/dev/null
sudo iptables -t nat -F KUBE-EXT-UQMCRMJZLI3FTLDP 2>/dev/null   # 80 端口相关
sudo iptables -t nat -F KUBE-EXT-CVG3OEGEH7H5P3HQ 2>/dev/null   # 443 端口相关

# 3. 如需彻底清理所有 k3s 相关 iptables 链
sudo iptables -t nat -F KUBE-EXT-CVG3OEGEH7H5P3HQ
sudo iptables -t nat -F KUBE-EXT-UQMCRMJZLI3FTLDP
sudo iptables -t nat -X KUBE-EXT-CVG3OEGEH7H5P3HQ
sudo iptables -t nat -X KUBE-EXT-UQMCRMJZLI3FTLDP
```

### 方案三：彻底卸载 k3s（如不再需要）

```bash
# 卸载 k3s 并删除所有数据
/usr/local/bin/k3s-uninstall.sh
```

## 验证清理结果

```bash
# 确认无进程监听 80/443
sudo ss -tlnp | grep -E ':443|:80'

# 确认 iptables NAT 规则已清除
sudo iptables -t nat -L -n | grep -E 'dpt:80|dpt:443'

# 确认无残留 containerd-shim 进程
ps aux | grep containerd-shim | grep k8s.io
```

## 注意事项

- 执行 `k3s-killall.sh` 后，如需重新启动 k3s，直接 `sudo systemctl start k3s` 即可，集群数据会保留。
- 手动清理 iptables 规则时需谨慎，避免误删其他服务的规则。建议先 `sudo iptables -t nat -L -n --line-numbers` 查看完整规则表再操作。
- 如果使用了 nftables 后端，还需同步清理 nft 规则：`sudo nft list ruleset` 检查并删除相关链。
