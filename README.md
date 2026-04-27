🚀 一、安装
realm install
➕ 二、创建转发（最常用）
1️⃣ 基础 TCP 转发
realm add --localPort 12345 --remoteHost 1.2.3.4 --remotePort 443
2️⃣ TLS 客户端模式
realm add \
  --localPort 12345 \
  --remoteHost example.com \
  --remotePort 443 \
  --protocol tls \
  --customSni example.com
3️⃣ WS 客户端模式
realm add \
  --localPort 12345 \
  --remoteHost example.com \
  --remotePort 80 \
  --protocol ws \
  --customHost example.com \
  --customPath ws
4️⃣ WSS 客户端模式
realm add \
  --localPort 12345 \
  --remoteHost example.com \
  --remotePort 443 \
  --protocol wss \
  --customHost example.com \
  --customSni example.com \
  --customPath ws
🖥️ 三、服务端模式（带证书）
5️⃣ TLS 服务端（自定义证书）
realm add \
  --localPort 443 \
  --remoteHost 127.0.0.1 \
  --remotePort 8080 \
  --protocol tls \
  --isServer true \
  --isSecure true \
  --customSni example.com
6️⃣ WSS 服务端（证书）
realm add \
  --localPort 443 \
  --remoteHost 127.0.0.1 \
  --remotePort 8080 \
  --protocol wss \
  --isServer true \
  --isSecure true \
  --customHost example.com \
  --customSni example.com \
  --customPath ws

证书放这里：

/etc/xshyun/realm/cert/443/example.com.crt
/etc/xshyun/realm/cert/443/example.com.key
🔧 四、高级参数示例
7️⃣ 开启 proxy protocol
realm add \
  --localPort 12345 \
  --remoteHost 1.2.3.4 \
  --remotePort 443 \
  --sendProxy true \
  --acceptProxy true
8️⃣ 不自动重启
realm add \
  --localPort 12345 \
  --remoteHost 1.2.3.4 \
  --remotePort 443 \
  --autoRestart false
9️⃣ 负载均衡模式（只生成配置不启动）
realm add \
  --localPort 12345 \
  --remoteHost 1.2.3.4 \
  --remotePort 443 \
  --isBalance true
▶️ 五、服务控制
🔟 启动
realm start --localPort 12345
1️⃣1️⃣ 停止
realm stop --localPort 12345
1️⃣2️⃣ 重启
realm restart --localPort 12345
1️⃣3️⃣ 查看状态
realm status --localPort 12345
❌ 六、删除
1️⃣4️⃣ 删除指定端口（配置 + 服务）
realm remove --localPort 12345

或

realm uninstall --localPort 12345
1️⃣5️⃣ 卸载全部
realm uninstall
📋 七、查看
1️⃣6️⃣ 查看所有服务
realm list
🧠 最常用组合（建议收藏）
# 安装
realm install

# 创建
realm add --localPort 12345 --remoteHost 1.2.3.4 --remotePort 443

# 停止
realm stop --localPort 12345

# 启动
realm start --localPort 12345

# 删除
realm uninstall --localPort 12345

# 查看
realm list
