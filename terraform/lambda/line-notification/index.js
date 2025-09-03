const axios = require('axios');

// Environment variables
const LINE_CHANNEL_ACCESS_TOKEN = process.env.LINE_CHANNEL_ACCESS_TOKEN;
const LINE_CHANNEL_SECRET = process.env.LINE_CHANNEL_SECRET;
const LINE_USER_ID = process.env.LINE_USER_ID;

// Line Messaging API endpoint
const LINE_API_URL = 'https://api.line.me/v2/bot/message/push';

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    try {
        // Parse the event (from IoT Rule or direct invocation)
        let notificationData;

        if (event.Records) {
            // If called from SNS or other AWS service
            notificationData = JSON.parse(event.Records[0].Sns.Message);
        } else if (event.topic) {
            // If called from IoT Rule
            notificationData = event;
        } else {
            // Direct invocation
            notificationData = event;
        }

        console.log('Notification data:', notificationData);

        // Determine message type and content
        let message;
        if (notificationData.topic === 'security-camera/motion-alert') {
            message = await createMotionAlertMessage(notificationData);
        } else if (notificationData.alertType === 'system') {
            message = await createSystemAlertMessage(notificationData);
        } else {
            message = await createGenericMessage(notificationData);
        }

        // Send Line message
        const result = await sendLineMessage(message);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Notification sent successfully',
                result: result
            })
        };

    } catch (error) {
        console.error('Error sending Line notification:', error);

        return {
            statusCode: 500,
            body: JSON.stringify({
                error: 'Failed to send notification',
                message: error.message
            })
        };
    }
};

async function createMotionAlertMessage(data) {
    const timestamp = new Date(data.timestamp || Date.now()).toLocaleString('ja-JP', {
        timeZone: 'Asia/Tokyo'
    });

    const message = {
        type: 'flex',
        altText: '🚨 動体検知アラート',
        contents: {
            type: 'bubble',
            header: {
                type: 'box',
                layout: 'vertical',
                contents: [
                    {
                        type: 'text',
                        text: '🚨 セキュリティアラート',
                        weight: 'bold',
                        size: 'lg',
                        color: '#FF0000'
                    }
                ],
                backgroundColor: '#FFE6E6'
            },
            body: {
                type: 'box',
                layout: 'vertical',
                contents: [
                    {
                        type: 'text',
                        text: '動体が検知されました',
                        weight: 'bold',
                        size: 'md',
                        margin: 'md'
                    },
                    {
                        type: 'separator',
                        margin: 'md'
                    },
                    {
                        type: 'box',
                        layout: 'vertical',
                        margin: 'md',
                        contents: [
                            {
                                type: 'box',
                                layout: 'baseline',
                                contents: [
                                    {
                                        type: 'text',
                                        text: '時刻:',
                                        size: 'sm',
                                        color: '#666666',
                                        flex: 2
                                    },
                                    {
                                        type: 'text',
                                        text: timestamp,
                                        size: 'sm',
                                        flex: 5,
                                        wrap: true
                                    }
                                ]
                            },
                            {
                                type: 'box',
                                layout: 'baseline',
                                contents: [
                                    {
                                        type: 'text',
                                        text: '場所:',
                                        size: 'sm',
                                        color: '#666666',
                                        flex: 2
                                    },
                                    {
                                        type: 'text',
                                        text: data.location || 'メインカメラ',
                                        size: 'sm',
                                        flex: 5
                                    }
                                ]
                            },
                            {
                                type: 'box',
                                layout: 'baseline',
                                contents: [
                                    {
                                        type: 'text',
                                        text: '信頼度:',
                                        size: 'sm',
                                        color: '#666666',
                                        flex: 2
                                    },
                                    {
                                        type: 'text',
                                        text: `${Math.round((data.confidence || 0.8) * 100)}%`,
                                        size: 'sm',
                                        flex: 5
                                    }
                                ]
                            }
                        ]
                    }
                ]
            },
            footer: {
                type: 'box',
                layout: 'vertical',
                contents: [
                    {
                        type: 'button',
                        action: {
                            type: 'uri',
                            label: '📹 ライブ映像を確認',
                            uri: data.cameraUrl || 'https://your-cloudfront-domain.com'
                        },
                        style: 'primary',
                        color: '#0066CC'
                    },
                    {
                        type: 'button',
                        action: {
                            type: 'uri',
                            label: '📁 録画を確認',
                            uri: data.recordingUrl || 'https://your-cloudfront-domain.com/recordings'
                        },
                        style: 'secondary',
                        margin: 'sm'
                    }
                ]
            }
        }
    };

    return message;
}

async function createSystemAlertMessage(data) {
    const timestamp = new Date(data.timestamp || Date.now()).toLocaleString('ja-JP', {
        timeZone: 'Asia/Tokyo'
    });

    const alertIcons = {
        error: '❌',
        warning: '⚠️',
        info: 'ℹ️',
        success: '✅'
    };

    const alertColors = {
        error: '#FF0000',
        warning: '#FFA500',
        info: '#0066CC',
        success: '#00AA00'
    };

    const alertType = data.severity || 'info';
    const icon = alertIcons[alertType] || 'ℹ️';
    const color = alertColors[alertType] || '#0066CC';

    const message = {
        type: 'flex',
        altText: `${icon} システム通知`,
        contents: {
            type: 'bubble',
            header: {
                type: 'box',
                layout: 'vertical',
                contents: [
                    {
                        type: 'text',
                        text: `${icon} システム通知`,
                        weight: 'bold',
                        size: 'lg',
                        color: color
                    }
                ]
            },
            body: {
                type: 'box',
                layout: 'vertical',
                contents: [
                    {
                        type: 'text',
                        text: data.message || 'システム通知があります',
                        wrap: true,
                        margin: 'md'
                    },
                    {
                        type: 'separator',
                        margin: 'md'
                    },
                    {
                        type: 'box',
                        layout: 'baseline',
                        margin: 'md',
                        contents: [
                            {
                                type: 'text',
                                text: '時刻:',
                                size: 'sm',
                                color: '#666666',
                                flex: 2
                            },
                            {
                                type: 'text',
                                text: timestamp,
                                size: 'sm',
                                flex: 5,
                                wrap: true
                            }
                        ]
                    }
                ]
            }
        }
    };

    return message;
}

async function createGenericMessage(data) {
    const timestamp = new Date(data.timestamp || Date.now()).toLocaleString('ja-JP', {
        timeZone: 'Asia/Tokyo'
    });

    return {
        type: 'text',
        text: `📹 セキュリティカメラ通知\n\n${data.message || 'お知らせがあります'}\n\n時刻: ${timestamp}`
    };
}

async function sendLineMessage(message) {
    if (!LINE_CHANNEL_ACCESS_TOKEN || !LINE_USER_ID) {
        throw new Error('Line configuration is missing');
    }

    const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`
    };

    const payload = {
        to: LINE_USER_ID,
        messages: [message]
    };

    console.log('Sending Line message:', JSON.stringify(payload, null, 2));

    try {
        const response = await axios.post(LINE_API_URL, payload, { headers });
        console.log('Line API response:', response.status, response.data);
        return response.data;
    } catch (error) {
        console.error('Line API error:', error.response?.data || error.message);
        throw error;
    }
} 