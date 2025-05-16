# Proxy 一键安装脚本

这是一个用于快速安装 [sing-box](https://github.com/SagerNet/sing-box) 的一键部署脚本。

脚本特点：
- 全自动下载安装，无需人工干预
- 自动注册为 systemd 服务并启动
- 失败时自动退出，确保稳定

## 使用方法

在 Linux 服务器上，运行以下命令：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Frank-dev-cn/proxy/main/install.sh)
```

```bash
nix=y uuid=d15974a0-3e66-4d08-b2c5-aefcaae3b717 vmpt=32156 agn=idx.frankdevcn.dpdns.org agk=eyJhIjoiZmEzN2I2NjYzYWM4OWQyNzYwNTYxN2U3MmYxZGFhYzYiLCJ0IjoiYTEyNWExY2EtNWM1YS00NWE2LWI3YmQtOGE2Y2VlYzhkMjMxIiwicyI6Ik9EbGpPVEEwTkdZdFpUVTFZaTAwWlRZekxXSmtPVFF0TlRBMVlUUXhaREZtT0dOaSJ9 bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosb/main/argosb.sh)
```

## xray
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Frank-dev-cn/proxy/main/install_xray.sh)
```
