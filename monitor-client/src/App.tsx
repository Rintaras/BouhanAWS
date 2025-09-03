import React, { useEffect, useRef, useState } from 'react'
import './App.css'
import {
    Video,
    Play,
    Trash2,
    Settings,
    AlertCircle,
    CheckCircle,
    FileVideo,
    Info,
    Wifi,
    WifiOff,
    Loader2,
    Power,
    X,
    Download
} from 'lucide-react'

interface MotionStatus {
    motion_detected: boolean
    recording_status: {
        is_recording: boolean
        recording_path: string | null
        duration: number
    }
}

interface Recording {
    filename: string
    size: number
    created: string
    modified: string
    thumbnail?: string
}

interface RecordingInfo {
    filename: string
    info: any
    size: number
    created: string
    modified: string
}

interface MotionSettings {
    threshold: number
    min_area: number
    motion_cooldown: number
}

const App: React.FC = () => {
    const videoRef = useRef<HTMLVideoElement>(null)
    const [isConnected, setIsConnected] = useState(false)
    const [isConnecting, setIsConnecting] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const [imageUrl, setImageUrl] = useState<string | null>(null)
    const [motionStatus, setMotionStatus] = useState<MotionStatus | null>(null)
    const [recordings, setRecordings] = useState<Recording[]>([])
    const [currentView, setCurrentView] = useState<'live' | 'recordings'>('live')
    const [selectedRecording, setSelectedRecording] = useState<Recording | null>(null)
    const [recordingInfo, setRecordingInfo] = useState<RecordingInfo | null>(null)
    const [motionSettings, setMotionSettings] = useState<MotionSettings>({
        threshold: 35,
        min_area: 2000,
        motion_cooldown: 3.0
    })
    const [showSettings, setShowSettings] = useState(false)
    const [lineNotifyStatus, setLineNotifyStatus] = useState<{
        enabled: boolean
        configured: boolean
    } | null>(null)

    // カメラサーバーのURLを動的に取得
    const getCameraServerUrl = () => {
        const currentHost = window.location.hostname;

        // CloudFront経由でアクセスした場合は同じCloudFrontのAPIエンドポイントを使用
        if (currentHost.includes('cloudfront.net') || currentHost.includes('s3-website')) {
            return '/api';
        }

        // ローカルネットワーク内の場合は直接Raspberry Piに接続
        if (currentHost === 'localhost' || currentHost === '127.0.0.1' ||
            currentHost === '172.20.10.2' || currentHost.includes('192.168.') ||
            currentHost.includes('10.') || currentHost.includes('172.')) {
            return 'http://172.20.10.2:3000';
        }

        // デフォルト
        return 'http://172.20.10.2:3000';
    }

    // カメラの起動状態を確認
    const checkCameraStatus = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/camera-status`)
            if (response.ok) {
                const status = await response.json()
                setIsConnected(status.is_active)
                if (status.is_active) {
                    // カメラが起動中なら映像を取得
                    fetchVideoFrame()
                }
            }
        } catch (err) {
            console.error('カメラ状態確認エラー:', err)
        }
    }

    // カメラを起動
    const startCamera = async () => {
        setIsConnecting(true)
        setError(null)

        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/camera/start`, {
                method: 'POST'
            })

            if (!response.ok) {
                throw new Error('カメラ起動に失敗しました')
            }

            const data = await response.json()

            if (data.error) {
                throw new Error(data.error)
            }

            setIsConnected(true)
            fetchVideoFrame()

            // 録画一覧ページの場合は即座に録画一覧を読み込む
            if (currentView === 'recordings') {
                fetchRecordings()
            }

            // 動き検知設定を取得
            fetchMotionSettings()

        } catch (err) {
            console.error('カメラ起動エラー:', err)

            // エラータイプに応じたメッセージを設定
            let errorMessage = 'カメラ起動に失敗しました'
            const currentHost = window.location.hostname

            if (err instanceof TypeError && err.message.includes('fetch')) {
                // ネットワークエラーの場合
                if (currentHost.includes('cloudfront.net')) {
                    errorMessage = `ネットワーク接続エラー: 外部からカメラサーバーにアクセスできません。
                    
同じWi-Fiネットワーク内から以下のURLでアクセスしてください：
http://172.20.10.2:8001

またはRaspberry Piと同じネットワークに接続してからお試しください。`
                } else {
                    errorMessage = 'カメラサーバーに接続できません。Raspberry Piが起動していることを確認してください。'
                }
            } else if (err instanceof Error) {
                errorMessage = err.message
            }

            setError(errorMessage)
        } finally {
            setIsConnecting(false)
        }
    }

    // カメラを停止
    const stopCamera = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/camera/stop`, {
                method: 'POST'
            })

            if (response.ok) {
                setIsConnected(false)
                setImageUrl(null)
                setError(null)
                setMotionStatus(null)
            }
        } catch (err) {
            console.error('カメラ停止エラー:', err)
        }
    }

    // 映像フレームを取得
    const fetchVideoFrame = async () => {
        try {
            const cameraUrl = getCameraServerUrl()

            // CloudFrontアクセス時は映像フレーム取得をスキップ
            if (cameraUrl === '/api') {
                setError('映像表示は同じWi-Fiネットワーク内からのみ利用可能です。\nカメラ制御機能は正常に動作します。')
                return
            }

            const response = await fetch(`${cameraUrl}/video-frame`)

            if (!response.ok) {
                throw new Error('映像取得に失敗しました')
            }

            const data = await response.json()

            if (data.error) {
                throw new Error(data.error)
            }

            setImageUrl(data.image)
        } catch (err) {
            console.error('映像取得エラー:', err)
            setError(err instanceof Error ? err.message : '映像取得に失敗しました')
        }
    }

    const fetchMotionStatus = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/motion-status`)
            if (response.ok) {
                const status = await response.json()
                setMotionStatus(status)
            }
        } catch (err) {
            console.error('動き検知状態取得エラー:', err)
        }
    }

    const fetchMotionSettings = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/motion-settings`)
            if (response.ok) {
                const settings = await response.json()
                setMotionSettings(settings)
            }
        } catch (err) {
            console.error('動き検知設定取得エラー:', err)
        }
    }

    const fetchLineMessagingStatus = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/line-messaging/status`)
            if (response.ok) {
                const status = await response.json()
                setLineNotifyStatus(status)
            }
        } catch (err) {
            console.error('LINE Messaging API状態取得エラー:', err)
        }
    }

    const testLineMessaging = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/line-messaging/test`, {
                method: 'POST'
            })
            if (response.ok) {
                alert('テスト通知を送信しました。LINEで確認してください。')
            } else {
                const error = await response.json()
                alert(`テスト通知送信に失敗しました: ${error.detail}`)
            }
        } catch (err) {
            console.error('LINE Messaging APIテストエラー:', err)
            alert('テスト通知送信に失敗しました')
        }
    }

    const updateMotionSettings = async (newSettings: Partial<MotionSettings>) => {
        try {
            const cameraUrl = getCameraServerUrl()
            const params = new URLSearchParams()

            if (newSettings.threshold !== undefined) params.append('threshold', newSettings.threshold.toString())
            if (newSettings.min_area !== undefined) params.append('min_area', newSettings.min_area.toString())
            if (newSettings.motion_cooldown !== undefined) params.append('motion_cooldown', newSettings.motion_cooldown.toString())

            const response = await fetch(`${cameraUrl}/motion-settings?${params.toString()}`, {
                method: 'POST'
            })
            if (response.ok) {
                const settings = await response.json()
                setMotionSettings(settings)
            }
        } catch (err) {
            console.error('動き検知設定更新エラー:', err)
        }
    }

    const fetchRecordings = async () => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/recordings`)
            if (response.ok) {
                const data = await response.json()
                setRecordings(data.recordings || [])
            }
        } catch (err) {
            console.error('録画一覧取得エラー:', err)
        }
    }

    const fetchRecordingInfo = async (filename: string) => {
        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/recordings/${filename}/info`)
            if (response.ok) {
                const info = await response.json()
                console.log('録画情報取得成功:', info)
                setRecordingInfo(info)
            } else {
                console.error('録画情報取得失敗:', response.status, response.statusText)
                // 基本的な情報のみ設定
                setRecordingInfo({
                    filename: filename,
                    info: null,
                    size: 0,
                    created: new Date().toISOString(),
                    modified: new Date().toISOString()
                })
            }
        } catch (err) {
            console.error('録画情報取得エラー:', err)
            // エラー時も基本的な情報を設定
            setRecordingInfo({
                filename: filename,
                info: null,
                size: 0,
                created: new Date().toISOString(),
                modified: new Date().toISOString()
            })
        }
    }

    const deleteRecording = async (filename: string) => {
        if (!confirm(`録画ファイル "${filename}" を削除しますか？`)) {
            return
        }

        try {
            const cameraUrl = getCameraServerUrl()
            const response = await fetch(`${cameraUrl}/recordings/${filename}`, {
                method: 'DELETE'
            })
            if (response.ok) {
                await fetchRecordings()
                if (selectedRecording?.filename === filename) {
                    setSelectedRecording(null)
                    setRecordingInfo(null)
                }
            }
        } catch (err) {
            console.error('録画削除エラー:', err)
        }
    }

    const playRecording = (recording: Recording) => {
        console.log('playRecordingが呼び出されました:', recording.filename);
        setSelectedRecording(recording);
        fetchRecordingInfo(recording.filename);
    }

    const handleDownload = async (filename: string) => {
        console.log('ダウンロードボタンがクリックされました:', filename);

        try {
            const downloadUrl = getDownloadUrl(filename);
            console.log('ダウンロードURL:', downloadUrl);
            console.log('ファイル名:', filename);

            // 方法1: fetchを使用してダウンロード
            console.log('fetchでダウンロードを開始...');
            const response = await fetch(downloadUrl);

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const blob = await response.blob();
            console.log('blobを取得しました:', blob.size, 'bytes');

            // blobからダウンロードリンクを作成
            const url = window.URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = filename;
            link.style.display = 'none';

            console.log('ダウンロードリンクを作成:', link.href);
            console.log('ダウンロードファイル名:', link.download);

            // リンクをDOMに追加してクリック
            document.body.appendChild(link);
            console.log('リンクをDOMに追加しました');

            link.click();
            console.log('リンクをクリックしました');

            // リンクを削除してblob URLを解放
            setTimeout(() => {
                try {
                    document.body.removeChild(link);
                    window.URL.revokeObjectURL(url);
                    console.log('リンクを削除し、blob URLを解放しました');
                } catch (removeError) {
                    console.log('リンク削除エラー:', removeError);
                }
            }, 100);

            console.log('ダウンロードを開始しました:', filename);
        } catch (error) {
            console.error('ダウンロードエラー:', error);
            console.log('エラーの詳細:', error);

            // エラー時は新しいタブで開く
            try {
                const fallbackUrl = getDownloadUrl(filename);
                console.log('フォールバックURL:', fallbackUrl);
                window.open(fallbackUrl, '_blank');
                console.log('新しいタブで動画を開きました');
            } catch (fallbackError) {
                console.error('フォールバックエラー:', fallbackError);
            }
        }
    };

    // コンポーネントマウント時にカメラ状態を確認
    useEffect(() => {
        checkCameraStatus()
    }, [])

    // 定期的に映像を更新（カメラが起動中の場合）
    useEffect(() => {
        if (!isConnected) return

        const interval = setInterval(() => {
            fetchVideoFrame()
        }, 100) // 10FPS

        return () => clearInterval(interval)
    }, [isConnected])

    // 動き検知状態を定期的に更新（カメラが起動中の場合）
    useEffect(() => {
        if (!isConnected) return

        const interval = setInterval(() => {
            fetchMotionStatus()
        }, 1000) // 1秒間隔

        return () => clearInterval(interval)
    }, [isConnected])

    // 定期的に録画一覧を更新
    useEffect(() => {
        if (currentView === 'recordings') {
            fetchRecordings() // 初回取得
            const interval = setInterval(fetchRecordings, 5000) // 5秒間隔で更新
            return () => clearInterval(interval)
        }
    }, [currentView])

    // 録画一覧ページにアクセスした時に即座に読み込む
    useEffect(() => {
        if (currentView === 'recordings') {
            fetchRecordings()
        }
    }, [currentView])

    // LINE Messaging APIの状態を取得
    useEffect(() => {
        fetchLineMessagingStatus()
    }, [])

    const formatFileSize = (bytes: number) => {
        if (bytes === 0) return '0 Bytes'
        const k = 1024
        const sizes = ['Bytes', 'KB', 'MB', 'GB']
        const i = Math.floor(Math.log(bytes) / Math.log(k))
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
    }

    const formatDate = (dateString: string) => {
        return new Date(dateString).toLocaleString('ja-JP')
    }

    const getVideoUrl = (filename: string) => {
        const cameraUrl = getCameraServerUrl()
        const url = `${cameraUrl}/recordings/${encodeURIComponent(filename)}`
        console.log('getVideoUrl - カメラサーバーURL:', cameraUrl);
        console.log('getVideoUrl - エンコードされたファイル名:', encodeURIComponent(filename));
        console.log('getVideoUrl - 生成されたURL:', url);
        return url
    }

    const getDownloadUrl = (filename: string) => {
        const cameraUrl = getCameraServerUrl()
        const url = `${cameraUrl}/recordings/${encodeURIComponent(filename)}?download=true`
        console.log('getDownloadUrl - カメラサーバーURL:', cameraUrl);
        console.log('getDownloadUrl - エンコードされたファイル名:', encodeURIComponent(filename));
        console.log('getDownloadUrl - 生成されたダウンロードURL:', url);
        return url
    }

    // HEADリクエストのテスト機能を削除（405エラーの原因）

    return (
        <div className="app">
            <header className="app-header">
                <div className="header-content">
                    <div className="status-indicator">
                        <span className={`status ${isConnected ? 'connected' : 'disconnected'}`}>
                            {isConnected ? <Wifi size={24} /> : <WifiOff size={24} />}
                        </span>
                    </div>
                    <nav className="navigation">
                        <button
                            className={`nav-button ${currentView === 'live' ? 'active' : ''}`}
                            onClick={() => setCurrentView('live')}
                        >
                            <Video size={20} />
                            ライブ映像
                        </button>
                        <button
                            className={`nav-button ${currentView === 'recordings' ? 'active' : ''}`}
                            onClick={() => {
                                setCurrentView('recordings')
                                fetchRecordings()
                            }}
                        >
                            <FileVideo size={20} />
                            録画一覧
                        </button>
                    </nav>
                </div>
            </header>

            <div className="app-content">
                <main className="main-content">
                    {/* ナビゲーション */}
                    {/* <div className="navigation">
                        <button
                            className={`nav-button ${currentView === 'live' ? 'active' : ''}`}
                            onClick={() => setCurrentView('live')}
                        >
                            <Video size={20} />
                            ライブ映像
                        </button>
                        <button
                            className={`nav-button ${currentView === 'recordings' ? 'active' : ''}`}
                            onClick={() => {
                                setCurrentView('recordings')
                                fetchRecordings()
                            }}
                        >
                            <FileVideo size={20} />
                            録画一覧
                        </button>
                    </div> */}

                    {currentView === 'live' ? (
                        <>
                            <div className="video-container">
                                {isConnected && imageUrl ? (
                                    <img
                                        src={imageUrl}
                                        alt="カメラ映像"
                                        className="camera-video"
                                    />
                                ) : (
                                    <div className="video-placeholder">
                                        <div className="placeholder-content">
                                            <div className="camera-icon">
                                                <Video size={48} />
                                            </div>
                                            <p>カメラ映像がここに表示されます</p>
                                            <p className="placeholder-subtitle">
                                                {isConnecting ? '接続中...' : '起動ボタンを押してカメラを開始してください'}
                                            </p>
                                        </div>
                                    </div>
                                )}
                            </div>

                            {/* 動き検知・録画状態表示 */}
                            {isConnected && motionStatus && (
                                <div className="motion-status">
                                    <div className={`motion-indicator ${motionStatus.motion_detected ? 'detected' : 'normal'}`}>
                                        <span className="motion-icon">
                                            {motionStatus.motion_detected ? <AlertCircle size={20} /> : <CheckCircle size={20} />}
                                        </span>
                                        <span className="motion-text">
                                            {motionStatus.motion_detected ? '動き検知中' : '通常状態'}
                                        </span>
                                    </div>

                                    {motionStatus.recording_status.is_recording && (
                                        <div className="recording-indicator">
                                            <span className="recording-icon">
                                                <Video size={20} />
                                            </span>
                                            <span className="recording-text">
                                                録画中 ({motionStatus.recording_status.duration.toFixed(1)}秒)
                                            </span>
                                        </div>
                                    )}

                                    <button
                                        onClick={() => setShowSettings(!showSettings)}
                                        className="settings-button"
                                    >
                                        <Settings size={16} />
                                        設定
                                    </button>
                                </div>
                            )}

                            {/* 設定パネル */}
                            {isConnected && showSettings && (
                                <div className="motion-settings-panel">
                                    <h4>
                                        <Settings size={20} />
                                        システム設定
                                    </h4>
                                    <div className="settings-grid">
                                        <div className="setting-item">
                                            <label>感度 (閾値): {motionSettings.threshold}</label>
                                            <input
                                                type="range"
                                                min="10"
                                                max="100"
                                                value={motionSettings.threshold}
                                                onChange={(e) => {
                                                    const value = parseInt(e.target.value)
                                                    setMotionSettings(prev => ({ ...prev, threshold: value }))
                                                    updateMotionSettings({ threshold: value })
                                                }}
                                            />
                                            <span className="setting-hint">低いほど敏感</span>
                                        </div>

                                        <div className="setting-item">
                                            <label>最小面積: {motionSettings.min_area}px</label>
                                            <input
                                                type="range"
                                                min="100"
                                                max="10000"
                                                step="100"
                                                value={motionSettings.min_area}
                                                onChange={(e) => {
                                                    const value = parseInt(e.target.value)
                                                    setMotionSettings(prev => ({ ...prev, min_area: value }))
                                                    updateMotionSettings({ min_area: value })
                                                }}
                                            />
                                            <span className="setting-hint">大きいほど大きな動きのみ検知</span>
                                        </div>

                                        <div className="setting-item">
                                            <label>クールダウン: {motionSettings.motion_cooldown}秒</label>
                                            <input
                                                type="range"
                                                min="1"
                                                max="10"
                                                step="0.5"
                                                value={motionSettings.motion_cooldown}
                                                onChange={(e) => {
                                                    const value = parseFloat(e.target.value)
                                                    setMotionSettings(prev => ({ ...prev, motion_cooldown: value }))
                                                    updateMotionSettings({ motion_cooldown: value })
                                                }}
                                            />
                                            <span className="setting-hint">動き終了後の録画継続時間</span>
                                        </div>
                                    </div>

                                    {/* LINE Messaging API設定 */}
                                    <div className="line-notify-section">
                                        <h5>📱 LINE Messaging API設定</h5>
                                        <div className="line-notify-status">
                                            <div className="status-item">
                                                <span className="status-label">通知状態:</span>
                                                <span className={`status-value ${lineNotifyStatus?.enabled ? 'enabled' : 'disabled'}`}>
                                                    {lineNotifyStatus?.enabled ? '有効' : '無効'}
                                                </span>
                                            </div>
                                            <div className="status-item">
                                                <span className="status-label">設定状態:</span>
                                                <span className={`status-value ${lineNotifyStatus?.configured ? 'configured' : 'not-configured'}`}>
                                                    {lineNotifyStatus?.configured ? '設定済み' : '未設定'}
                                                </span>
                                            </div>
                                        </div>
                                        <div className="line-notify-actions">
                                            <button
                                                onClick={testLineMessaging}
                                                disabled={!lineNotifyStatus?.enabled}
                                                className="test-notify-button"
                                            >
                                                テスト通知送信
                                            </button>

                                        </div>
                                        <div className="line-notify-info">
                                            <p>📋 LINE Messaging APIの設定方法:</p>
                                            <ol>
                                                <li><a href="https://developers.line.biz/console/" target="_blank" rel="noopener noreferrer">LINE Developers Console</a>にアクセス</li>
                                                <li>LINEアカウントでログイン</li>
                                                <li>新しいプロバイダーを作成</li>
                                                <li>新しいチャネルを作成（Messaging API）</li>
                                                <li>チャネルアクセストークン（長期）を取得</li>
                                                <li>ユーザーIDを取得（LINEアプリでボットを友達追加後）</li>
                                                <li>Raspberry Piで環境変数として設定</li>
                                            </ol>
                                        </div>
                                    </div>
                                </div>
                            )}

                            <div className="controls">
                                {isConnected ? (
                                    <button onClick={stopCamera} className="disconnect-button">
                                        <Power size={16} />
                                        切断
                                    </button>
                                ) : (
                                    <button
                                        onClick={startCamera}
                                        disabled={isConnecting}
                                        className="connect-button"
                                    >
                                        {isConnecting ? (
                                            <>
                                                <Loader2 size={16} className="spinning" />
                                                接続中...
                                            </>
                                        ) : (
                                            <>
                                                <Wifi size={16} />
                                                カメラを起動
                                            </>
                                        )}
                                    </button>
                                )}
                            </div>
                        </>
                    ) : (
                        <div className="recordings-view">
                            <div className="recordings-list-container">
                                <h3>
                                    <FileVideo size={24} />
                                    録画ファイル一覧
                                </h3>
                                <div className="recordings-list">
                                    {recordings.length > 0 ? (
                                        recordings.map((recording, index) => (
                                            <div key={index} className="recording-item">
                                                <div
                                                    className="recording-info"
                                                    onClick={(event) => {
                                                        // ボタンがクリックされた場合は動画再生を防ぐ
                                                        const target = event.target as HTMLElement;
                                                        if (target.closest('button')) {
                                                            console.log('ボタンがクリックされたため動画再生をスキップします');
                                                            return;
                                                        }
                                                        console.log('録画アイテムがクリックされました。動画再生を開始します:', recording.filename);
                                                        playRecording(recording);
                                                    }}
                                                >
                                                    {recording.thumbnail ? (
                                                        <div className="recording-thumbnail">
                                                            <img
                                                                src={`${getCameraServerUrl()}/thumbnails/${recording.thumbnail}`}
                                                                alt="録画サムネイル"
                                                                className="thumbnail-image"
                                                                onError={(e) => {
                                                                    console.log(`サムネイル読み込みエラー: ${recording.thumbnail}`);
                                                                    e.currentTarget.style.display = 'none';
                                                                }}
                                                                onLoad={() => {
                                                                    console.log(`サムネイル読み込み成功: ${recording.thumbnail}`);
                                                                }}
                                                            />
                                                        </div>
                                                    ) : (
                                                        <div className="recording-thumbnail">
                                                            <div className="thumbnail-placeholder">
                                                                <FileVideo size={48} />
                                                                <span>サムネイルなし</span>
                                                            </div>
                                                        </div>
                                                    )}
                                                    <div className="recording-text-info">
                                                        <div className="recording-name">{recording.filename}</div>
                                                        <div className="recording-details">
                                                            <span>サイズ: {formatFileSize(recording.size)}</span>
                                                            <span>作成: {formatDate(recording.created)}</span>
                                                            <span>録画: {(() => {
                                                                // ファイル名から日時を抽出 (motion_YYYYMMDD_HHMMSS.mp4)
                                                                const match = recording.filename.match(/motion_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.mp4/)
                                                                if (match) {
                                                                    const [, year, month, day, hour, minute, second] = match
                                                                    const date = new Date(
                                                                        parseInt(year),
                                                                        parseInt(month) - 1,
                                                                        parseInt(day),
                                                                        parseInt(hour),
                                                                        parseInt(minute),
                                                                        parseInt(second)
                                                                    )
                                                                    return date.toLocaleString('ja-JP', {
                                                                        month: '2-digit',
                                                                        day: '2-digit',
                                                                        hour: '2-digit',
                                                                        minute: '2-digit'
                                                                    })
                                                                }
                                                                return '不明'
                                                            })()}</span>
                                                        </div>
                                                    </div>
                                                </div>
                                                <div className="recording-actions">
                                                    <button
                                                        onClick={(event) => {
                                                            event.stopPropagation();
                                                            playRecording(recording);
                                                        }}
                                                        className="play-button"
                                                    >
                                                        <Play size={16} />
                                                        再生
                                                    </button>
                                                    <button
                                                        onClick={(event) => {
                                                            event.stopPropagation();
                                                            deleteRecording(recording.filename);
                                                        }}
                                                        className="delete-button"
                                                    >
                                                        <Trash2 size={16} />
                                                        削除
                                                    </button>
                                                    <button
                                                        onClick={() => {
                                                            console.log('ダウンロードボタンがクリックされました');
                                                            handleDownload(recording.filename);
                                                        }}
                                                        className="download-button"
                                                        title="ダウンロード"
                                                    >
                                                        <Download size={16} />
                                                    </button>
                                                </div>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="no-recordings">
                                            <p>録画ファイルがありません</p>
                                        </div>
                                    )}
                                </div>
                            </div>

                            {selectedRecording && (
                                <div className="video-player-container">
                                    <div className="video-player-header">
                                        <h3>
                                            <Play size={20} />
                                            録画再生
                                        </h3>
                                        <button
                                            onClick={() => setSelectedRecording(null)}
                                            className="minimize-button"
                                            title="最小化"
                                        >
                                            <X size={16} />
                                        </button>
                                    </div>
                                    <div className="video-player">
                                        <video
                                            ref={videoRef}
                                            controls
                                            className="recording-video"
                                            src={getVideoUrl(selectedRecording.filename)}
                                            onLoadedMetadata={(e) => {
                                                console.log('動画メタデータ読み込み完了');
                                                // 再生速度を100ms間隔に設定（120FPS → 10FPS相当）
                                                const video = e.target as HTMLVideoElement;
                                                video.playbackRate = 0.1; // 100ms間隔（10FPS）
                                                console.log('再生速度を設定:', video.playbackRate);
                                            }}
                                            onError={(e) => {
                                                console.error('動画再生エラー:', e);
                                                console.error('動画URL:', getVideoUrl(selectedRecording.filename));
                                                console.error('エラー詳細:', e.nativeEvent);

                                                // エラーの詳細分析
                                                const videoElement = e.target as HTMLVideoElement;
                                                console.error('動画要素の状態:', {
                                                    readyState: videoElement.readyState,
                                                    networkState: videoElement.networkState,
                                                    error: videoElement.error
                                                });

                                                // エラーメッセージをより具体的に
                                                const errorMessage = '動画の再生に失敗しました。\n\n考えられる原因:\n• 動画ファイルが破損している\n• ブラウザが動画形式をサポートしていない\n• ネットワーク接続の問題\n• CORS設定の問題\n\nブラウザのコンソールで詳細を確認してください。\n\n対処法:\n• ブラウザを更新してください\n• 別のブラウザで試してください\n• ダウンロードボタンでファイルを保存してください';
                                                alert(errorMessage);
                                            }}
                                            onLoadStart={() => console.log('動画読み込み開始')}
                                            onCanPlay={() => console.log('動画再生可能')}
                                            onLoadedData={() => console.log('動画データ読み込み完了')}
                                            onProgress={() => console.log('動画読み込み進行中')}
                                            onSuspend={() => console.log('動画読み込み一時停止')}
                                            onAbort={() => console.log('動画読み込み中断')}
                                            onStalled={() => console.log('動画読み込み停止')}
                                            onWaiting={() => console.log('動画読み込み待機中')}
                                            onCanPlayThrough={() => console.log('動画再生準備完了')}
                                            onDurationChange={() => console.log('動画長さ変更')}
                                            onRateChange={() => console.log('再生速度変更')}
                                            onVolumeChange={() => console.log('音量変更')}
                                            preload="metadata"
                                        >
                                            お使いのブラウザは動画再生をサポートしていません。
                                        </video>
                                    </div>
                                    {recordingInfo && (
                                        <div className="recording-details-panel">
                                            <h4>
                                                <Info size={20} />
                                                録画詳細
                                            </h4>
                                            <div className="details-grid">
                                                <div className="detail-item">
                                                    <span className="detail-label">ファイル名:</span>
                                                    <span className="detail-value">{recordingInfo.filename || 'N/A'}</span>
                                                </div>
                                                <div className="detail-item">
                                                    <span className="detail-label">録画日時:</span>
                                                    <span className="detail-value">
                                                        {(() => {
                                                            // ファイル名から日時を抽出 (motion_YYYYMMDD_HHMMSS.mp4)
                                                            if (recordingInfo.filename) {
                                                                const match = recordingInfo.filename.match(/motion_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.mp4/)
                                                                if (match) {
                                                                    const [, year, month, day, hour, minute, second] = match
                                                                    const date = new Date(
                                                                        parseInt(year),
                                                                        parseInt(month) - 1,
                                                                        parseInt(day),
                                                                        parseInt(hour),
                                                                        parseInt(minute),
                                                                        parseInt(second)
                                                                    )
                                                                    return date.toLocaleString('ja-JP', {
                                                                        year: 'numeric',
                                                                        month: '2-digit',
                                                                        day: '2-digit',
                                                                        hour: '2-digit',
                                                                        minute: '2-digit',
                                                                        second: '2-digit'
                                                                    })
                                                                }
                                                            }
                                                            return recordingInfo.created ? formatDate(recordingInfo.created) : 'N/A'
                                                        })()}
                                                    </span>
                                                </div>
                                                <div className="detail-item">
                                                    <span className="detail-label">サイズ:</span>
                                                    <span className="detail-value">{recordingInfo.size ? formatFileSize(recordingInfo.size) : 'N/A'}</span>
                                                </div>
                                                <div className="detail-item">
                                                    <span className="detail-label">作成日時:</span>
                                                    <span className="detail-value">{recordingInfo.created ? formatDate(recordingInfo.created) : 'N/A'}</span>
                                                </div>
                                                {recordingInfo.info?.format && (
                                                    <>
                                                        <div className="detail-item">
                                                            <span className="detail-label">長さ:</span>
                                                            <span className="detail-value">{parseFloat(recordingInfo.info.format.duration).toFixed(1)}秒</span>
                                                        </div>
                                                        <div className="detail-item">
                                                            <span className="detail-label">フレームレート:</span>
                                                            <span className="detail-value">{recordingInfo.info.streams?.[0]?.r_frame_rate || 'N/A'}</span>
                                                        </div>
                                                        <div className="detail-item">
                                                            <span className="detail-label">解像度:</span>
                                                            <span className="detail-value">{recordingInfo.info.streams?.[0]?.width || 'N/A'}x{recordingInfo.info.streams?.[0]?.height || 'N/A'}</span>
                                                        </div>
                                                    </>
                                                )}
                                            </div>
                                            <div className="recording-actions-details">
                                                <button
                                                    onClick={() => {
                                                        console.log('詳細パネルのダウンロードボタンがクリックされました');
                                                        if (recordingInfo.filename) {
                                                            handleDownload(recordingInfo.filename);
                                                        }
                                                    }}
                                                    className="download-button"
                                                    title="ダウンロード"
                                                >
                                                    <Download size={16} />
                                                </button>
                                            </div>
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>
                    )}

                    {error && (
                        <div className="error-message">
                            <p>
                                <AlertCircle size={16} />
                                エラー: {error}
                            </p>
                        </div>
                    )}
                </main>
            </div>
        </div>
    )
}

export default App 