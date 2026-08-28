# 1. 创建配置目录（如果不存在）
sudo mkdir -p /etc/rancher/k3s

# 2. 生成包含多个国内源的配置文件
sudo tee /etc/rancher/k3s/registries.yaml << 'EOF'
mirrors:
  docker.io:
    endpoint:
      # 腾讯云内部源（对你当前服务器网络最佳）
      - "https://mirror.ccs.tencentyun.com"
      # 1panel 源
      - "https://docker.1panel.live"
      # 1ms.run 源
      - "https://1ms.run"
      # 中科大源
      - "https://docker.mirrors.ustc.edu.cn"
      # 官方源作为最后的保底
      - "https://registry-1.docker.io"
EOF

# 3. 重启 K3s 服务使配置生效
sudo systemctl restart k3s
