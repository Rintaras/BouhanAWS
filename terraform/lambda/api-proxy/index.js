const AWS = require('aws-sdk');
const axios = require('axios');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

// AWS Services
const dynamodb = new AWS.DynamoDB.DocumentClient();
const iotdata = new AWS.IotData({
    endpoint: process.env.IOT_ENDPOINT
});

// Environment variables
const RASPBERRY_PI_IP = process.env.RASPBERRY_PI_IP;
const RASPBERRY_PI_PORT = process.env.RASPBERRY_PI_PORT || '3000';
const DYNAMODB_TABLE = process.env.DYNAMODB_TABLE;
const IOT_THING_NAME = process.env.IOT_THING_NAME;

// Default credentials (should be changed in production)
const DEFAULT_USERNAME = 'admin';
const DEFAULT_PASSWORD_HASH = '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'; // password: admin123
const JWT_SECRET = 'your-super-secret-jwt-key';

// AWS IoT command sender
async function sendIoTCommand(command, data = {}) {
    const message = {
        command: command,
        data: data,
        timestamp: new Date().toISOString(),
        requestId: uuidv4()
    };

    const params = {
        topic: `security-camera/${IOT_THING_NAME}/commands`,
        payload: JSON.stringify(message),
        qos: 1
    };

    try {
        await iotdata.publish(params).promise();
        console.log(`IoT command sent: ${command}`, message);
        return { success: true, requestId: message.requestId };
    } catch (error) {
        console.error('IoT command send error:', error);
        throw error;
    }
}

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    try {
        const { httpMethod, path, pathParameters, queryStringParameters, headers, body } = event;
        const requestBody = body ? JSON.parse(body) : {};

        // CORS headers
        const corsHeaders = {
            'Access-Control-Allow-Origin': 'https://d3n8o5om0tprho.cloudfront.net',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
            'Content-Type': 'application/json'
        };

        // Handle OPTIONS request (CORS preflight)
        if (httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }

        // Extract path from proxy
        const apiPath = pathParameters?.proxy || '';
        console.log('API Path:', apiPath);

        // Route handling
        switch (true) {
            case apiPath === 'auth/login' && httpMethod === 'POST':
                return await handleLogin(requestBody, corsHeaders);

            case apiPath === 'auth/logout' && httpMethod === 'POST':
                return await handleLogout(headers, corsHeaders);

            case apiPath === 'health' && httpMethod === 'GET':
                return await handleHealth(corsHeaders);

            // Camera status endpoint
            case apiPath === 'camera-status' && httpMethod === 'GET':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, null, headers, corsHeaders, 'GET');

            // Line messaging endpoints
            case apiPath === 'line-messaging/status' && httpMethod === 'GET':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, null, headers, corsHeaders, 'GET');

            case apiPath === 'line-messaging/test' && httpMethod === 'POST':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, requestBody, headers, corsHeaders, 'POST');

            // Video frame endpoint
            case apiPath === 'video-frame' && httpMethod === 'GET':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, null, headers, corsHeaders, 'GET');

            // Motion endpoints
            case apiPath === 'motion-status' && httpMethod === 'GET':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, null, headers, corsHeaders, 'GET');

            case apiPath === 'motion-settings' && httpMethod === 'GET':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, null, headers, corsHeaders, 'GET');

            case apiPath === 'motion-settings' && httpMethod === 'POST':
                return await handleRaspberryPiProxy(apiPath, queryStringParameters, requestBody, headers, corsHeaders, 'POST');

            case apiPath.startsWith('camera/') && httpMethod === 'GET':
                return await handleCameraRequest(apiPath, queryStringParameters, headers, corsHeaders);

            case apiPath.startsWith('camera/') && httpMethod === 'POST':
                return await handleCameraCommand(apiPath, requestBody, headers, corsHeaders);

            case apiPath.startsWith('recordings') && httpMethod === 'GET':
                return await handleRecordingsRequest(apiPath, queryStringParameters, headers, corsHeaders);

            default:
                return {
                    statusCode: 404,
                    headers: corsHeaders,
                    body: JSON.stringify({ error: 'Not found', path: apiPath })
                };
        }

    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': 'https://d3n8o5om0tprho.cloudfront.net',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};

// Authentication functions
async function handleLogin(body, corsHeaders) {
    const { username, password } = body;

    if (!username || !password) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Username and password required' })
        };
    }

    // Simple authentication (should be enhanced for production)
    if (username === DEFAULT_USERNAME && await bcrypt.compare(password, DEFAULT_PASSWORD_HASH)) {
        const sessionId = uuidv4();
        const token = jwt.sign({ username, sessionId }, JWT_SECRET, { expiresIn: '24h' });

        // Store session in DynamoDB
        await dynamodb.put({
            TableName: DYNAMODB_TABLE,
            Item: {
                session_id: sessionId,
                user_id: username,
                created_at: Date.now(),
                expires_at: Date.now() + (24 * 60 * 60 * 1000) // 24 hours
            }
        }).promise();

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ token, sessionId })
        };
    } else {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid credentials' })
        };
    }
}

async function handleLogout(headers, corsHeaders) {
    const token = extractToken(headers);
    if (!token) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'No token provided' })
        };
    }

    try {
        const decoded = jwt.verify(token, JWT_SECRET);

        // Remove session from DynamoDB
        await dynamodb.delete({
            TableName: DYNAMODB_TABLE,
            Key: { session_id: decoded.sessionId }
        }).promise();

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ message: 'Logged out successfully' })
        };
    } catch (error) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid token' })
        };
    }
}

// Health check
async function handleHealth(corsHeaders) {
    try {
        // Check Raspberry Pi connectivity
        const raspberryPiUrl = `http://${RASPBERRY_PI_IP}:${RASPBERRY_PI_PORT}/health`;
        const response = await axios.get(raspberryPiUrl, { timeout: 5000 });

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                status: 'healthy',
                timestamp: new Date().toISOString(),
                raspberry_pi_status: response.data
            })
        };
    } catch (error) {
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                status: 'partial',
                timestamp: new Date().toISOString(),
                raspberry_pi_status: 'unreachable',
                error: error.message
            })
        };
    }
}

// Generic Raspberry Pi proxy handler (no authentication required)
async function handleRaspberryPiProxy(path, queryParams, body, headers, corsHeaders, method) {
    try {
        const raspberryPiUrl = `http://${RASPBERRY_PI_IP}:${RASPBERRY_PI_PORT}/${path}`;
        const queryString = queryParams ? new URLSearchParams(queryParams).toString() : '';
        const fullUrl = queryString ? `${raspberryPiUrl}?${queryString}` : raspberryPiUrl;

        console.log('Proxying to:', fullUrl);

        const config = {
            timeout: method === 'GET' && path === 'video-frame' ? 30000 : 10000,
            responseType: path.includes('video') ? 'stream' : 'json'
        };

        let response;
        if (method === 'POST') {
            response = await axios.post(fullUrl, body, config);
        } else {
            response = await axios.get(fullUrl, config);
        }

        if (path.includes('video') || path === 'video-frame') {
            // Handle video/image responses
            if (response.data.image) {
                // JSON response with base64 image
                return {
                    statusCode: 200,
                    headers: corsHeaders,
                    body: JSON.stringify(response.data)
                };
            } else {
                // Binary data response
                return {
                    statusCode: 200,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': response.headers['content-type'] || 'application/octet-stream',
                        'Cache-Control': 'no-cache'
                    },
                    body: response.data.toString('base64'),
                    isBase64Encoded: true
                };
            }
        } else {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify(response.data)
            };
        }
    } catch (error) {
        console.error('Raspberry Pi proxy request failed:', error.message);
        return {
            statusCode: 502,
            headers: corsHeaders,
            body: JSON.stringify({
                error: 'Raspberry Pi unreachable',
                message: error.message,
                path: path
            })
        };
    }
}

// Camera request handling
async function handleCameraRequest(path, queryParams, headers, corsHeaders) {
    const authResult = await authenticateRequest(headers);
    if (authResult.error) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify(authResult)
        };
    }

    try {
        const raspberryPiUrl = `http://${RASPBERRY_PI_IP}:${RASPBERRY_PI_PORT}/${path}`;
        const queryString = queryParams ? new URLSearchParams(queryParams).toString() : '';
        const fullUrl = queryString ? `${raspberryPiUrl}?${queryString}` : raspberryPiUrl;

        console.log('Proxying to:', fullUrl);

        const response = await axios.get(fullUrl, {
            timeout: 30000,
            responseType: path.includes('video') ? 'stream' : 'json'
        });

        if (path.includes('video')) {
            // Handle video streaming
            return {
                statusCode: 200,
                headers: {
                    ...corsHeaders,
                    'Content-Type': response.headers['content-type'] || 'video/mp4',
                    'Cache-Control': 'no-cache'
                },
                body: response.data.toString('base64'),
                isBase64Encoded: true
            };
        } else {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify(response.data)
            };
        }
    } catch (error) {
        console.error('Raspberry Pi request failed:', error.message);
        return {
            statusCode: 502,
            headers: corsHeaders,
            body: JSON.stringify({
                error: 'Raspberry Pi unreachable',
                message: error.message
            })
        };
    }
}

// Camera command handling
async function handleCameraCommand(path, body, headers, corsHeaders) {
    // 一時的に認証をバイパス（テスト用）
    // const authResult = await authenticateRequest(headers);
    // if (authResult.error) {
    //     return {
    //         statusCode: 401,
    //         headers: corsHeaders,
    //         body: JSON.stringify(authResult)
    //     };
    // }

    try {
        const commandType = path.replace('camera/', '');
        console.log(`Camera command: ${commandType}`, body);

        // Send command via IoT Core using unified function
        const result = await sendIoTCommand(commandType, body || {});

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                message: `Camera ${commandType} command sent successfully`,
                success: true,
                requestId: result.requestId,
                timestamp: new Date().toISOString()
            })
        };
    } catch (error) {
        console.error('Camera command failed:', error);
        return {
            statusCode: 502,
            headers: corsHeaders,
            body: JSON.stringify({
                error: 'Camera command failed',
                message: error.message,
                success: false
            })
        };
    }
}

// Recordings request handling
async function handleRecordingsRequest(path, queryParams, headers, corsHeaders) {
    const authResult = await authenticateRequest(headers);
    if (authResult.error) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify(authResult)
        };
    }

    try {
        const raspberryPiUrl = `http://${RASPBERRY_PI_IP}:${RASPBERRY_PI_PORT}/${path}`;
        const queryString = queryParams ? new URLSearchParams(queryParams).toString() : '';
        const fullUrl = queryString ? `${raspberryPiUrl}?${queryString}` : raspberryPiUrl;

        const response = await axios.get(fullUrl, { timeout: 10000 });

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify(response.data)
        };
    } catch (error) {
        console.error('Recordings request failed:', error.message);
        return {
            statusCode: 502,
            headers: corsHeaders,
            body: JSON.stringify({
                error: 'Recordings service unreachable',
                message: error.message
            })
        };
    }
}

// Utility functions
function extractToken(headers) {
    const authHeader = headers?.Authorization || headers?.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
        return authHeader.substring(7);
    }
    return null;
}

async function authenticateRequest(headers) {
    const token = extractToken(headers);
    if (!token) {
        return { error: 'No token provided' };
    }

    try {
        const decoded = jwt.verify(token, JWT_SECRET);

        // Check if session exists in DynamoDB
        const session = await dynamodb.get({
            TableName: DYNAMODB_TABLE,
            Key: { session_id: decoded.sessionId }
        }).promise();

        if (!session.Item) {
            return { error: 'Session not found' };
        }

        if (session.Item.expires_at < Date.now()) {
            return { error: 'Session expired' };
        }

        return { user: decoded };
    } catch (error) {
        return { error: 'Invalid token' };
    }
} 