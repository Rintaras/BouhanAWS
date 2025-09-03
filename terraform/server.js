const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const rateLimit = require('express-rate-limit');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const RASPBERRY_PI_IP = process.env.RASPBERRY_PI_IP;
const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key';

// ミドルウェア
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS設定
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
    if (req.method === 'OPTIONS') {
        res.sendStatus(200);
    } else {
        next();
    }
});

// レート制限
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15分
    max: 100, // IPアドレスごとに100リクエスト
    message: 'Too many requests from this IP'
});

app.use('/api', limiter);

// 認証ミドルウェア
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.sendStatus(401);
    }

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) return res.sendStatus(403);
        req.user = user;
        next();
    });
};

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'OK', timestamp: new Date().toISOString() });
});

// 認証エンドポイント
app.post('/auth/login', async (req, res) => {
    const { username, password } = req.body;

    // 簡単な認証（本番環境では適切なユーザー管理を実装）
    const validUsername = process.env.AUTH_USERNAME || 'admin';
    const validPasswordHash = process.env.AUTH_PASSWORD_HASH || await bcrypt.hash('admin123', 10);

    if (username === validUsername && await bcrypt.compare(password, validPasswordHash)) {
        const token = jwt.sign({ username }, JWT_SECRET, { expiresIn: '24h' });
        res.json({ token });
    } else {
        res.status(401).json({ error: 'Invalid credentials' });
    }
});

// Raspberry Piへのプロキシ設定
const proxyOptions = {
    target: `http://${RASPBERRY_PI_IP}:3000`,
    changeOrigin: true,
    timeout: 30000,
    proxyTimeout: 30000,
    onError: (err, req, res) => {
        console.error('Proxy error:', err);
        res.status(500).json({
            error: 'Proxy error',
            message: 'Cannot connect to camera server',
            timestamp: new Date().toISOString()
        });
    },
    onProxyReq: (proxyReq, req, res) => {
        console.log(`Proxying ${req.method} ${req.url} to ${proxyReq.path}`);
    }
};

// 認証が必要なAPIエンドポイント
app.use('/api', authenticateToken, createProxyMiddleware(proxyOptions));

// 公開エンドポイント（ヘルスチェックなど）
app.use('/health-check', createProxyMiddleware({
    ...proxyOptions,
    pathRewrite: {
        '^/health-check': '/health'
    }
}));

// 静的ファイル配信（フロントエンド）
app.use(express.static('public'));

// SPA用のフォールバック
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Proxy server running on port ${PORT}`);
    console.log(`Proxying requests to Raspberry Pi at ${RASPBERRY_PI_IP}:3000`);
}); 