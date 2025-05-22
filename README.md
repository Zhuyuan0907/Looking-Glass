# Looking-Glass
因為網路上的Looking Glass不適合我，所以叫Claude寫了一個出來

#使用說明
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
一樣
