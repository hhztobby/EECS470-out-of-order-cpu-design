#!/bin/bash

# 运行 read_reg.py 脚本
echo "正在运行 read_reg.py..."
python3 read_reg.py
kill $(lsof -t -i:8000)

# 检查是否执行成功
if [ $? -ne 0 ]; then
  echo "read_reg.py 执行失败，退出脚本。"
  exit 1
fi

# 启动 HTTP 服务器
echo "启动 HTTP 服务器，监听端口 8000..."
python3 -m http.server 8000 &

# 给服务器一点时间启动
sleep 2

# 打开默认浏览器访问服务器地址
if command -v xdg-open >/dev/null; then
  xdg-open http://localhost:8000
elif command -v open >/dev/null; then
  open http://localhost:8000
else
  echo "无法自动打开浏览器，请手动访问 http://localhost:8000"
fi

# 等待 HTTP 服务器结束
wait
