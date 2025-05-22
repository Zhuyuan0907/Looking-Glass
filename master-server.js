// master-server.js - Looking Glass Master 服務器
const express = require('express');
const { spawn } = require('child_process');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const fs = require('fs');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;

// 載入配置
let config;
try {
    config = JSON.parse(fs.readFileSync('master-config.json', 'utf8'));
} catch (error) {
    console.error('無法載入配置文件:', error.message);
    process.exit(1);
}

// 中間件
app.use(cors({
    origin: config.security.allowedOrigins || ['http://localhost:3000', 'http://127.0.0.1:3000'],
    credentials: true
}));

app.use(express.json());
app.use(express.static('public'));

// 速率限制
const limiter = rateLimit({
    windowMs: config.security.rateLimitWindow || 60000,
    max: config.security.rateLimitMax || 15,
    message: { error: '請求過於頻繁，請稍後再試' },
    standardHeaders: true,
    legacyHeaders: false,
});

app.use('/api/', limiter);

// Slave 節點通信類
class SlaveNodeManager {
    constructor() {
        this.slaveNodes = new Map();
        this.loadSlaveNodes();
        this.startHealthCheck();
    }

    // 載入 Slave 節點配置
    loadSlaveNodes() {
        config.nodes.forEach(node => {
            if (node.type === 'slave' && node.slaveConfig) {
                this.slaveNodes.set(node.id, {
                    ...node,
                    lastHealthCheck: null,
                    isHealthy: false
                });
            }
        });
        console.log(`載入了 ${this.slaveNodes.size} 個 Slave 節點`);
    }

    // 向 Slave 節點發送請求
    async sendToSlave(nodeId, endpoint, data = null, timeout = 30000) {
        const node = this.slaveNodes.get(nodeId);
        if (!node) {
            throw new Error(`找不到節點: ${nodeId}`);
        }

        const url = `http://${node.slaveConfig.host}:${node.slaveConfig.port}${endpoint}`;
        const headers = {
            'Content-Type': 'application/json',
            'X-API-Key': node.slaveConfig.apiKey
        };

        try {
            let response;
            if (data) {
                response = await axios.post(url, data, { headers, timeout });
            } else {
                response = await axios.get(url, { headers, timeout });
            }
            
            return response.data;
        } catch (error) {
            console.error(`Slave 節點 ${nodeId} 通信失敗:`, error.message);
            throw new Error(`節點通信失敗: ${error.message}`);
        }
    }

    // 檢查 Slave 節點健康狀態
    async checkSlaveHealth(nodeId) {
        try {
            const result = await this.sendToSlave(nodeId, '/health', null, 5000);
            const node = this.slaveNodes.get(nodeId);
            if (node) {
                node.lastHealthCheck = new Date().toISOString();
                node.isHealthy = result.success;
                
                // 更新主配置中的狀態
                const configNode = config.nodes.find(n => n.id === nodeId);
                if (configNode) {
                    configNode.status = result.success ? 'online' : 'offline';
                }
            }
            return result.success;
        } catch (error) {
            const node = this.slaveNodes.get(nodeId);
            if (node) {
                node.isHealthy = false;
                node.lastHealthCheck = new Date().toISOString();
                
                const configNode = config.nodes.find(n => n.id === nodeId);
                if (configNode) {
                    configNode.status = 'offline';
                }
            }
            return false;
        }
    }

    // 啟動健康檢查
    startHealthCheck() {
        // 立即檢查一次
        this.performHealthCheck();
        
        // 定期檢查（每2分鐘）
        setInterval(() => {
            this.performHealthCheck();
        }, 2 * 60 * 1000);
    }

    // 執行健康檢查
    async performHealthCheck() {
        console.log('開始 Slave 節點健康檢查...');
        const promises = Array.from(this.slaveNodes.keys()).map(nodeId => 
            this.checkSlaveHealth(nodeId)
        );
        
        try {
            await Promise.allSettled(promises);
            const healthyCount = Array.from(this.slaveNodes.values())
                .filter(node => node.isHealthy).length;
            console.log(`健康檢查完成: ${healthyCount}/${this.slaveNodes.size} 個節點正常`);
        } catch (error) {
            console.error('健康檢查失敗:', error.message);
        }
    }
}

// 初始化 Slave 節點管理器
const slaveManager = new SlaveNodeManager();

// 驗證目標主機
function isValidTarget(target) {
    const ipv4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
    const hostnameRegex = /^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$/;
    
    if (target.length > 253) return false;
    if (!ipv4Regex.test(target) && !hostnameRegex.test(target)) return false;
    
    const blacklist = config.security.blacklistedTargets || [];
    if (blacklist.some(blocked => target.includes(blocked))) return false;
    
    return true;
}

// 本地命令執行（用於 Master 節點本身的測試）
function executeLocalCommand(command, args, timeout = 30000) {
    return new Promise((resolve, reject) => {
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

// API 路由

// 獲取節點列表
app.get('/api/nodes', (req, res) => {
    res.json({
        success: true,
        nodes: config.nodes.map(node => ({
            id: node.id,
            name: node.name,
            location: node.location,
            ipv4: node.ipv4,
            ipv6: node.ipv6,
            provider: node.provider,
            status: node.status,
            type: node.type || 'local',
            description: node.description,
            coordinates: node.coordinates
        }))
    });
});

// 獲取特定節點資訊
app.get('/api/nodes/:nodeId', async (req, res) => {
    const nodeId = req.params.nodeId;
    const node = config.nodes.find(n => n.id === nodeId);
    
    if (!node) {
        return res.status(404).json({
            success: false,
            error: '節點不存在'
        });
    }
    
    // 如果是 Slave 節點，嘗試獲取詳細資訊
    if (node.type === 'slave') {
        try {
            const slaveInfo = await slaveManager.sendToSlave(nodeId, '/info', null, 10000);
            res.json({
                success: true,
                node: {
                    ...node,
                    slaveInfo: slaveInfo.nodeInfo
                }
            });
        } catch (error) {
            res.json({
                success: true,
                node: node,
                error: '無法獲取 Slave 節點詳細資訊'
            });
        }
    } else {
        res.json({
            success: true,
            node: node
        });
    }
});

// 執行 Ping 測試
app.post('/api/ping', async (req, res) => {
    const { target, nodeId } = req.body;
    
    if (!target || !nodeId) {
        return res.status(400).json({
            success: false,
            error: '缺少必要參數'
        });
    }
    
    const node = config.nodes.find(n => n.id === nodeId);
    if (!node) {
        return res.status(404).json({
            success: false,
            error: '節點不存在'
        });
    }
    
    if (node.status !== 'online') {
        return res.status(503).json({
            success: false,
            error: '節點目前離線'
        });
    }
    
    if (!isValidTarget(target)) {
        return res.status(400).json({
            success: false,
            error: '無效的目標主機'
        });
    }
    
    try {
        let result;
        
        if (node.type === 'slave') {
            // 發送到 Slave 節點執行
            result = await slaveManager.sendToSlave(nodeId, '/ping', { target }, 30000);
        } else {
            // 在本地執行
            const args = ['-c', '4', '-W', '5', target];
            const output = await executeLocalCommand('ping', args, 20000);
            result = {
                success: true,
                command: `ping ${args.join(' ')}`,
                output: output,
                nodeId: nodeId,
                timestamp: new Date().toISOString()
            };
        }
        
        res.json({
            ...result,
            node: {
                id: node.id,
                name: node.name,
                location: node.location
            }
        });
        
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message,
            command: `ping -c 4 -W 5 ${target}`
        });
    }
});

// 執行 MTR 測試
app.post('/api/mtr', async (req, res) => {
    const { target, nodeId } = req.body;
    
    if (!target || !nodeId) {
        return res.status(400).json({
            success: false,
            error: '缺少必要參數'
        });
    }
    
    const node = config.nodes.find(n => n.id === nodeId);
    if (!node) {
        return res.status(404).json({
            success: false,
            error: '節點不存在'
        });
    }
    
    if (node.status !== 'online') {
        return res.status(503).json({
            success: false,
            error: '節點目前離線'
        });
    }
    
    if (!isValidTarget(target)) {
        return res.status(400).json({
            success: false,
            error: '無效的目標主機'
        });
    }
    
    try {
        let result;
        
        if (node.type === 'slave') {
            // 發送到 Slave 節點執行
            result = await slaveManager.sendToSlave(nodeId, '/mtr', { target }, 90000);
        } else {
            // 在本地執行
            const args = ['--report', '--report-cycles', '10', target];
            const output = await executeLocalCommand('mtr', args, 90000);
            result = {
                success: true,
                command: `mtr ${args.join(' ')}`,
                output: output,
                nodeId: nodeId,
                timestamp: new Date().toISOString()
            };
        }
        
        res.json({
            ...result,
            node: {
                id: node.id,
                name: node.name,
                location: node.location
            }
        });
        
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message,
            command: `mtr --report --report-cycles 10 ${target}`
        });
    }
});

// 健康檢查
app.get('/api/health', (req, res) => {
    const slaveStatus = Array.from(slaveManager.slaveNodes.entries()).map(([id, node]) => ({
        nodeId: id,
        isHealthy: node.isHealthy,
        lastCheck: node.lastHealthCheck
    }));
    
    res.json({
        success: true,
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '2.0.0',
        slaveNodes: slaveStatus
    });
});

// 錯誤處理中間件
app.use((error, req, res, next) => {
    console.error('服務器錯誤:', error);
    res.status(500).json({
        success: false,
        error: '內部服務器錯誤'
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
    console.log(`=== Looking Glass Master 節點啟動 ===`);
    console.log(`運行端口: ${PORT}`);
    console.log(`總節點數: ${config.nodes.length}`);
    console.log(`本地節點: ${config.nodes.filter(n => n.type !== 'slave').length}`);
    console.log(`Slave 節點: ${slaveManager.slaveNodes.size}`);
    console.log('================================');
});

// 優雅關閉
process.on('SIGINT', () => {
    console.log('\n正在關閉 Master 服務器...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n正在關閉 Master 服務器...');
    process.exit(0);
});
