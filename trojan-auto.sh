#!/bin/bash
set -e

echo "========= Trojan-Go 一键交互安装脚本 ========="

# 0. 脚本自我净化，自动转unix格式（即便有\r\n也直接修复）
if command -v dos2unix >/dev/null 2>&1; then
  dos2unix "$0" >/dev/null 2>&1 || true
else
  apt update && apt install -y dos2unix
  dos2unix "$0" >/dev/null 2>&1 || true
fi

# 1. 输入参数
read -p "请输入你要绑定的域名（已解析到本VPS）: " DOMAIN
read -p "请输入你想设置的Trojan密码: " TROJAN_PASS
read -p "请输入Cloudflare账号邮箱: " CF_EMAIL
read -p "请输入Cloudflare Global API Key: " CF_KEY

# 2. 系统更新&依赖
apt update && apt upgrade -y
apt install -y wget curl unzip socat nano ufw dos2unix

# 3. 安装 acme.sh 并设定LetsEncrypt为CA
if [ ! -d "$HOME/.acme.sh" ]; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 4. Cloudflare API 环境变量
export CF_Email="$CF_EMAIL"
export CF_Key="$CF_KEY"
if ! grep -q 'CF_Email' ~/.bashrc; then
  echo "export CF_Email=\"$CF_EMAIL\"" >> ~/.bashrc
  echo "export CF_Key=\"$CF_KEY\"" >> ~/.bashrc
fi

# 5. 申请 ECC 证书
~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength ec-256
if [ $? -ne 0 ]; then
    echo "证书申请失败，请检查域名解析和Cloudflare API Key设置！"
    exit 1
fi

# 6. 拷贝证书到trojan-go目录
mkdir -p /etc/trojan
cp ~/.acme.sh/${DOMAIN}_ecc/fullchain.cer /etc/trojan/
cp ~/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key /etc/trojan/private.key

# 7. 下载并安装 Trojan-Go
cd /opt
wget -O trojan-go.zip https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
unzip -o trojan-go.zip
mv -f trojan-go /usr/local/bin/
chmod +x /usr/local/bin/trojan-go

# 8. 生成配置文件
cat > /etc/trojan/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 1,
  "password": [
    "$TROJAN_PASS"
  ],
  "ssl": {
    "cert": "/etc/trojan/fullchain.cer",
    "key": "/etc/trojan/private.key",
    "sni": "$DOMAIN"
  }
}
EOF

# 9. 创建 systemd 服务
cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go - Secure Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

# 10. 防火墙放行（如有ufw）
if command -v ufw >/dev/null 2>&1; then
  ufw allow 443/tcp
  ufw reload
fi

echo ""
echo "========= 安装完成！========="
echo "Trojan-Go已启动，客户端连接参数如下："
echo "服务器地址：$DOMAIN"
echo "端口：443"
echo "密码：$TROJAN_PASS"
echo "SNI：$DOMAIN"
echo ""
echo "请在客户端选择 trojan-go 或 trojan 协议即可使用。"
echo ""
echo "如遇问题，运行  systemctl status trojan-go -l  查看详细报错。"
