#!/bin/bash

# Looking Glass 自動安裝腳本
# 支持 Master 和 Slave 節點安裝

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日誌函數
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 檢查是否為 root 用戶
check_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "不建議以 root 用戶運行此腳本"
        read -p "是否繼續？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 檢查系統類型
check_system() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log "檢測到 Linux 系統"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log "檢測到 macOS 系統"
    else
        error "不支持的系統類型: $OSTYPE"
    fi
}

# 安裝系統依賴
install_system_deps() {
    log "安裝系統依賴..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y curl wget gnupg2 software-properties-common
        sudo apt-get install -y iputils-ping traceroute mtr-tiny dnsutils
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        sudo yum update -y
        sudo yum install -y curl wget gnupg2
        sudo yum install -y iputils traceroute mtr bind-utils
    elif command -v brew >/dev/null 2>&1; then
        # macOS
        brew install mtr
    else
        error "無法檢測到支持的包管理器"
    fi
}

# 安裝 Node.js
install_nodejs() {
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version)
        log "Node.js 已安裝: $NODE_VERSION"
        
        # 檢查版本是否符合要求
        NODE_MAJOR=$(echo $NODE_VERSION | cut -d'.' -f1 | sed 's/v//')
        if [[ $NODE_MAJOR -lt 14 ]]; then
            warn "Node.js 版本過低，建議升級到 14.0+"
        fi
    else
        log "安裝 Node.js..."
        
        if command -v apt-get >/dev/null 2>&1; then
            # 使用 NodeSource 倉庫
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif command -v yum >/dev/null 2>&1; then
            # CentOS/RHEL
            curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
            sudo yum install -y nodejs
        elif command -v brew >/dev/null 2>&1; then
            # macOS
            brew install node
        else
            error "無法自動安裝 Node.js，請手動安裝"
        fi
    fi
    
    # 驗證安裝
    node --version || error "Node.js 安裝失敗"
    npm --version || error "npm 安裝失敗"
}

# 創建用戶和目錄
setup_user_and_dirs() {
    local node_type=$1
    local install_dir="/opt/looking-glass"
    
    if [[ "$node_type" == "slave" ]]; then
        install_dir="/opt/looking-glass-slave"
    fi
    
    # 創建目錄
    sudo mkdir -p $install_dir
    sudo mkdir -p $install_dir/logs
    sudo mkdir -p /var/log/looking-glass
    
    # 設置權限
    sudo chown -R $USER:$USER $install_dir
    sudo chmod -R 755 $install_dir
    
    echo $install_dir
}

# 安裝 Master 節點
install_master() {
    log "安裝 Looking Glass Master 節點..."
    
    local install_dir=$(setup_user_and_dirs "master")
    cd $install_dir
    
    # 創建 package.json
    cat > package.json << 'EOF'
{
  "name": "looking-glass-master",
  "version": "2.0.0",
  "description": "Looking Glass Master Node",
  "main": "master-server.js",
  "scripts": {
    "start": "node master-server.js",
    "dev": "nodemon master-server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "express-rate-limit": "^6.7.0",
    "axios": "^1.4.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
EOF
    
    # 安裝依賴
    npm install
    
    # 創建基本配置文件
    if [[ ! -f "master-config.json" ]]; then
        log "創建基本配置文件..."
        cat > master-config.json << 'EOF'
{
  "nodes": [
    {
      "id": "master-local",
      "name": "本地主控節點",
      "location": "本地",
      "ipv4": "127.0.0.1",
      "type": "local",
      "status": "online"
    }
  ],
  "security": {
    "rateLimitWindow": 60000,
    "rateLimitMax": 20,
    "allowedOrigins": ["http://localhost:3000"],
    "blockPrivateNetworks": false,
    "blacklistedTargets": []
  },
  "settings": {
    "pingTimeout": 30000,
    "tracerouteTimeout": 60000,
    "maxHops": 20,
    "pingCount": 4
  }
}
EOF
        warn "請編輯 master-config.json 文件以配置您的節點"
    fi
    
    # 創建 public 目錄
    mkdir -p public
    
    log "Master 節點安裝完成！"
    log "安裝路徑: $install_dir"
    log "請將 master-server.js 和前端文件放到此目錄"
}

# 安裝 Slave 節點
install_slave() {
    log "安裝 Looking Glass Slave 節點..."
    
    local install_dir=$(setup_user_and_dirs "slave")
    cd $install_dir
    
    # 創建 package.json
    cat > package.json << 'EOF'
{
  "name": "looking-glass-slave",
  "version": "2.0.0",
  "description": "Looking Glass Slave Node Agent",
  "main": "slave-agent.js",
  "scripts": {
    "start": "node slave-agent.js",
    "dev": "nodemon slave-agent.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
EOF
    
    # 安裝依賴
    npm install
    
    # 創建完整的 slave-agent.js
    cat > slave-agent.js << 'EOF'
// slave-agent.js - Slave 節點代理程序
const express = require('express');
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');

const app = express();
app.use(express.json());

// 載入配置
let config;
try {
    config = JSON.parse(fs.readFileSync('slave-config.json', 'utf8'));
} catch (error) {
    console.error('無法載入 Slave 配置文件:', error.message);
    process.exit(1);
}

const PORT = config.port || 3001;
const API_KEY = config.apiKey;

// 驗證 API Key 中間件
function authenticateApiKey(req, res, next) {
    const apiKey = req.headers['x-api-key'];
    
    if (!apiKey || apiKey !== API_KEY) {
        return res.status(401).json({
            success: false,
            error: '未授權訪問'
        });
    }
    
    next();
}

// 記錄請求
function logRequest(req, res, next) {
    const timestamp = new Date().toISOString();
    const ip = req.ip || req.connection.remoteAddress;
    console.log(`[${timestamp}] ${req.method} ${req.path} - ${ip}`);
    next();
}

app.use(logRequest);
app.use(authenticateApiKey);

// 驗證目標主機
function isValidTarget(target) {
    const ipv4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    const hostnameRegex = /^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$/;
    
    if (target.length > 253) return false;
    if (!ipv4Regex.test(target) && !hostnameRegex.test(target)) return false;
    
    // 檢查黑名單
    const blacklist = config.security?.blacklistedTargets || [];
    if (blacklist.some(blocked => target.includes(blocked))) return false;
    
    return true;
}

// 檢查是否為私有網路
function isPrivateNetwork(ip) {
    const ipv4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    if (!ipv4Regex.test(ip)) return false;
    
    const parts = ip.split('.').map(Number);
    
    if (parts[0] === 10) return true;
    if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    if (parts[0] === 192 && parts[1] === 168) return true;
    if (parts[0] === 127) return true;
    
    return false;
}

// 執行系統命令
function executeCommand(command, args, timeout = 30000) {
    return new Promise((resolve, reject) => {
        console.log(`執行命令: ${command} ${args.join(' ')}`);
        
        const process = spawn(command, args, {
            stdio: ['ignore', 'pipe', 'pipe'],
            timeout: timeout
        });
        
        let stdout = '';
        let stderr = '';
        
        process.stdout.on('data', (data) => {
            stdout += data.toString();
        });
        
        process.stderr.on('data', (data) => {
            stderr += data.toString();
        });
        
        process.on('close', (code) => {
            if (code === 0) {
                resolve(stdout);
            } else {
                reject(new Error(stderr || `命令執行失敗，退出代碼: ${code}`));
            }
        });
        
        process.on('error', (error) => {
            reject(error);
        });
        
        setTimeout(() => {
            if (!process.killed) {
                process.kill('SIGTERM');
                reject(new Error('命令執行超時'));
            }
        }, timeout);
    });
}

// 獲取節點資訊
app.get('/info', (req, res) => {
    const networkInterfaces = os.networkInterfaces();
    const primaryInterface = Object.keys(networkInterfaces).find(name => 
        networkInterfaces[name].some(iface => 
            !iface.internal && iface.family === 'IPv4'
        )
    );
    
    const primaryIP = primaryInterface ? 
        networkInterfaces[primaryInterface].find(iface => 
            !iface.internal && iface.family === 'IPv4'
        ).address : 'unknown';

    res.json({
        success: true,
        nodeInfo: {
            id: config.nodeId,
            name: config.nodeName,
            location: config.location,
            hostname: os.hostname(),
            platform: os.platform(),
            arch: os.arch(),
            uptime: os.uptime(),
            loadavg: os.loadavg(),
            memory: {
                total: os.totalmem(),
                free: os.freemem()
            },
            network: {
                primaryIP: primaryIP,
                interfaces: Object.keys(networkInterfaces)
            }
        },
        timestamp: new Date().toISOString()
    });
});

// 健康檢查
app.get('/health', (req, res) => {
    res.json({
        success: true,
        status: 'healthy',
        nodeId: config.nodeId,
        timestamp: new Date().toISOString()
    });
});

// 執行 Ping 測試
app.post('/ping', async (req, res) => {
    const { target, count = 4, timeout = 5 } = req.body;
    
    if (!target) {
        return res.status(400).json({
            success: false,
            error: '缺少目標主機參數'
        });
    }
    
    if (!isValidTarget(target)) {
        return res.status(400).json({
            success: false,
            error: '無效的目標主機'
        });
    }
    
    // 檢查是否為私有網路（如果啟用阻擋）
    if (config.security?.blockPrivateNetworks && isPrivateNetwork(target)) {
        return res.status(400).json({
            success: false,
            error: '不允許測試私有網路'
        });
    }
    
    try {
        const args = ['-c', count.toString(), '-W', timeout.toString(), target];
        const output = await executeCommand('ping', args, 30000);
        
        res.json({
            success: true,
            command: `ping ${args.join(' ')}`,
            output: output,
            nodeId: config.nodeId,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('Ping 執行失敗:', error.message);
        res.status(500).json({
            success: false,
            error: error.message,
            command: `ping -c ${count} -W ${timeout} ${target}`
        });
    }
});

// 執行 MTR 測試
app.post('/mtr', async (req, res) => {
    const { target, cycles = 10 } = req.body;
    
    if (!target) {
        return res.status(400).json({
            success: false,
            error: '缺少目標主機參數'
        });
    }
    
    if (!isValidTarget(target)) {
        return res.status(400).json({
            success: false,
            error: '無效的目標主機'
        });
    }
    
    if (config.security?.blockPrivateNetworks && isPrivateNetwork(target)) {
        return res.status(400).json({
            success: false,
            error: '不允許測試私有網路'
        });
    }
    
    try {
        const args = ['--report', '--report-cycles', cycles.toString(), target];
        const output = await executeCommand('mtr', args, 90000);
        
        res.json({
            success: true,
            command: `mtr ${args.join(' ')}`,
            output: output,
            nodeId: config.nodeId,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('MTR 執行失敗:', error.message);
        res.status(500).json({
            success: false,
            error: 'MTR 不可用或執行失敗: ' + error.message,
            command: `mtr --report --report-cycles ${cycles} ${target}`
        });
    }
});

// 錯誤處理
app.use((error, req, res, next) => {
    console.error('伺服器錯誤:', error);
    res.status(500).json({
        success: false,
        error: '內部伺服器錯誤'
    });
});

// 404 處理
app.use((req, res) => {
    res.status(404).json({
        success: false,
        error: '找不到請求的資源'
    });
});

// 啟動服務器
app.listen(PORT, () => {
    console.log(`=== Slave 節點代理啟動 ===`);
    console.log(`節點 ID: ${config.nodeId}`);
    console.log(`節點名稱: ${config.nodeName}`);
    console.log(`運行端口: ${PORT}`);
    console.log(`API Key: ${API_KEY ? '已設定' : '未設定'}`);
    console.log('========================');
});

// 優雅關閉
process.on('SIGINT', () => {
    console.log('\n正在關閉 Slave 節點...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n正在關閉 Slave 節點...');
    process.exit(0);
});
EOF
    
    # 設置執行權限
    chmod +x slave-agent.js
    
    # 創建基本配置文件
    if [[ ! -f "slave-config.json" ]]; then
        log "創建基本配置文件..."
        
        # 獲取本機 IP
        LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
        
        cat > slave-config.json << EOF
{
  "nodeId": "slave-$(hostname)",
  "nodeName": "$(hostname) 節點",
  "location": "請設置位置",
  "port": 3001,
  "apiKey": "請設置安全的API密鑰",
  "masterNodes": [
    {
      "ip": "MASTER_NODE_IP",
      "port": 3000,
      "description": "主控節點"
    }
  ],
  "security": {
    "blockPrivateNetworks": false,
    "blacklistedTargets": []
  },
  "settings": {
    "maxConcurrentTests": 3,
    "defaultPingCount": 4,
    "defaultPingTimeout": 5,
    "defaultMtrCycles": 10
  }
}
EOF
        warn "請編輯 slave-config.json 文件以配置您的節點"
    fi
    
    log "Slave 節點安裝完成！"
    log "安裝路徑: $install_dir"
    log "配置文件: $install_dir/slave-config.json"
    log ""
    log "下一步："
    log "1. 編輯配置文件設置節點資訊和 API 密鑰"
    log "2. 在 Master 節點配置中添加此 Slave 節點"
    log "3. 啟動服務: sudo systemctl start looking-glass-slave"
}

# 安裝 PM2
install_pm2() {
    if command -v pm2 >/dev/null 2>&1; then
        log "PM2 已安裝"
    else
        log "安裝 PM2..."
        sudo npm install -g pm2
    fi
}

# 創建系統服務
create_systemd_service() {
    local node_type=$1
    local install_dir=$2
    
    if [[ "$node_type" == "master" ]]; then
        local service_name="looking-glass-master"
        local exec_file="master-server.js"
    else
        local service_name="looking-glass-slave"
        local exec_file="slave-agent.js"
    fi
    
    log "創建 systemd 服務: $service_name"
    
    sudo tee /etc/systemd/system/$service_name.service > /dev/null << EOF
[Unit]
Description=Looking Glass $node_type Node
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$install_dir
ExecStart=/usr/bin/node $exec_file
Restart=always
RestartSec=10
Environment=NODE_ENV=production
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$service_name

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $service_name
    
    log "系統服務 $service_name 已創建並啟用"
}

# 顯示使用說明
show_usage() {
    echo "Looking Glass 安裝腳本"
    echo ""
    echo "使用方法:"
    echo "  $0 master    # 安裝 Master 節點"  
    echo "  $0 slave     # 安裝 Slave 節點"
    echo "  $0 deps      # 只安裝系統依賴"
    echo ""
    echo "選項:"
    echo "  --no-service    # 不創建系統服務"
    echo "  --no-pm2        # 不安裝 PM2"
    echo ""
}

# 主函數
main() {
    local node_type=""
    local create_service=true
    local install_pm2_flag=true
    
    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            master|slave|deps)
                node_type=$1
                shift
                ;;
            --no-service)
                create_service=false
                shift
                ;;
            --no-pm2)
                install_pm2_flag=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "未知參數: $1"
                ;;
        esac
    done
    
    if [[ -z "$node_type" ]]; then
        show_usage
        exit 1
    fi
    
    log "開始安裝 Looking Glass $node_type 節點..."
    
    # 檢查系統
    check_root
    check_system
    
    # 安裝基礎依賴
    install_system_deps
    install_nodejs
    
    if [[ "$install_pm2_flag" == true ]]; then
        install_pm2
    fi
    
    # 根據類型安裝
    case $node_type in
        master)
            install_dir=$(install_master)
            if [[ "$create_service" == true ]]; then
                create_systemd_service "master" "$install_dir"
            fi
            ;;
        slave)
            install_dir=$(install_slave)
            if [[ "$create_service" == true ]]; then
                create_systemd_service "slave" "$install_dir"
            fi
            ;;
        deps)
            log "系統依賴安裝完成"
            exit 0
            ;;
    esac
    
    log "安裝完成！"
    echo ""
    echo "後續步驟:"
    echo "1. 將相應的 JavaScript 文件放到安裝目錄"
    echo "2. 編輯配置文件"
    echo "3. 啟動服務:"
    
    if [[ "$create_service" == true ]]; then
        echo "   sudo systemctl start looking-glass-$node_type"
        echo "   sudo systemctl status looking-glass-$node_type"
    else
        echo "   cd $install_dir"
        echo "   npm start"
    fi
    
    if [[ "$install_pm2_flag" == true ]]; then
        echo ""
        echo "或使用 PM2:"
        echo "   cd $install_dir"
        if [[ "$node_type" == "master" ]]; then
            echo "   pm2 start master-server.js --name lg-master"
        else
            echo "   pm2 start slave-agent.js --name lg-slave"
        fi
        echo "   pm2 startup"
        echo "   pm2 save"
    fi
    
    echo ""
    echo "配置文件位置: $install_dir"
    echo "日誌位置: /var/log/looking-glass"
}

# 執行主函數
main "$@"
