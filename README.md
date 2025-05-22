# Looking-Glass
因為網路上的Looking Glass不適合我，所以叫Claude寫了一個出來

# 使用說明
該Looking Glass是具有能夠多開節點的功能
主端為Master，其他節點則統一為Slave
兩端之間，可用像是Wireguard、GRE、Vxlan等方式進行連結
使用的是本身自己的API，未來可嘗試更改成Globalping API

# 使用方法
## Master
首先先更新apt，安裝nodejs，以及clone專案下來
```
apt update
git clone https://github.com/Zhuyuan0907/Looking-Glass
cd Looking-Glass
apt install npm -y
```
進到資料夾之後，讓我們先把專案需要的套件都先install下來
```
npm install
```
然後我們要進去設定config的部分，按照自己需求設置即可
```
nano master-config.json
```
設置完之後，可以選擇用node master-server.js開啟，或是用下面的方式
```
npm start
```
接著就可以上 http://你的IP:3000 來查看網頁了！

## Slave
一樣，首先要先更新apt，然後clone腳本下來
```
apt update
apt install git -y
git clone https://github.com/Zhuyuan0907/Looking-Glass
cd Looking-Glass
```
不過，我們這次只有要使用裡面的install.sh，安裝完後就可以把整個資料夾刪除了
執行install.sh後，安裝slave相關文件
```
chmod +x install.sh
./install.sh slave
```
請記得打上YES
```
y
```
接著，我們要去slave的config文件，去配置與Master端通信
注意，Port的部分都是固定的，不需要去更動，Slave一律皆為3001
然後apikey兩者之間要相同
```
nano /opt/looking-glass-slave/slave-config.json
```
倒數第二步驟，要更改systemctl的設定
```
sudo tee /etc/systemd/system/looking-glass-slave.service > /dev/null << 'EOF'
[Unit]
Description=Looking Glass Slave Node
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/looking-glass-slave
ExecStart=/usr/bin/node slave-agent.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=looking-glass-slave

[Install]
WantedBy=multi-user.target
EOF
```
最後，重新restart daemon和systemctl
```
sudo systemctl daemon-reload
sudo systemctl enable looking-glass-slave
sudo systemctl start looking-glass-slave
sudo systemctl status looking-glass-slave
```
恭喜，Slave端配置完成
接著請重開你的Master端，看看有沒有連接成功
# 成果展示
![image](https://github.com/user-attachments/assets/c9a07a90-bfb1-4e35-b0a1-9a44a9ab3706)
