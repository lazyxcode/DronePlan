// Copyright (c) 2026 acche. All rights reserved.
import { useState, useCallback, useMemo, useRef } from 'react'
import { MapContainer, TileLayer, Marker, Polyline, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { invoke } from '@tauri-apps/api/core'

// Types
interface Waypoint {
    id: string
    latitude: number
    longitude: number
    altitude: number
    speed: number
    holdTime: number
}

interface FlightPlan {
    name: string
    waypoints: Waypoint[]
    cruiseSpeed: number
    maxAltitude: number
    cameraAngle: number
}

interface TileProvider {
    name: string
    url: string
    attribution: string
}

const tileProviders: TileProvider[] = [
    {
        name: 'OpenStreetMap',
        url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    },
    {
        name: 'CARTO Light',
        url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
        attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    },
    {
        name: 'Esri World Imagery',
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        attribution: 'Tiles &copy; Esri',
    },
]

// Custom marker icon
const waypointIcon = (index: number) => L.divIcon({
    className: 'waypoint-marker',
    html: `<div style="
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: #0071e3;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 600;
    box-shadow: 0 2px 8px rgba(0,113,227,0.4);
    border: 2px solid white;
  ">${index + 1}</div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
})

// Map click handler component
function MapClickHandler({ onMapClick }: { onMapClick: (lat: number, lng: number) => void }) {
    useMapEvents({
        click: (e) => {
            onMapClick(e.latlng.lat, e.latlng.lng)
        },
    })
    return null
}

function App() {
    const importSteps = [
        '先在 DJI Fly 里刚创建一个占位任务，确保 RC 2 已生成最新任务文件。',
        '点击“同步到 RC 2”，程序会在 Windows 下尝试直连遥控器并覆盖最新占位任务。',
        '如果当前电脑或固件下无法直连，再退回“导出 KMZ”走 microSD 中转。',
        '回到 DJI Fly 检查任务名称、航点数量和预览轨迹，确认无误后再执行飞行。',
    ]

    const workflowNotes = [
        '当前版本优先尝试 Windows 直连同步，背后调用本地 PowerShell helper 访问 RC 2 的 MTP 设备。',
        '同步逻辑会优先寻找 DJI Fly 任务目录里最近修改的占位 `.kmz` 进行覆盖。',
        '内部计算按 WGS84 生成，导出前请确认地图点位与目标区域一致。',
    ]

    const [plan, setPlan] = useState<FlightPlan>({
        name: '新建飞行计划',
        waypoints: [],
        cruiseSpeed: 8,
        maxAltitude: 120,
        cameraAngle: -45,
    })
    const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null)
    const [isExporting, setIsExporting] = useState(false)
    const [isSyncing, setIsSyncing] = useState(false)
    const [lastExportPath, setLastExportPath] = useState<string | null>(null)
    const [tileProviderIndex, setTileProviderIndex] = useState(0)
    const tileFallbackLock = useRef(false)

    // Show toast notification
    const showToast = useCallback((message: string, type: 'success' | 'error' = 'success') => {
        setToast({ message, type })
        setTimeout(() => setToast(null), 3000)
    }, [])

    // Add waypoint
    const handleMapClick = useCallback((lat: number, lng: number) => {
        const newWaypoint: Waypoint = {
            id: crypto.randomUUID(),
            latitude: lat,
            longitude: lng,
            altitude: plan.maxAltitude,
            speed: plan.cruiseSpeed,
            holdTime: 0,
        }
        setPlan(prev => ({
            ...prev,
            waypoints: [...prev.waypoints, newWaypoint],
        }))
    }, [plan.maxAltitude, plan.cruiseSpeed])

    // Remove waypoint
    const removeWaypoint = useCallback((id: string) => {
        setPlan(prev => ({
            ...prev,
            waypoints: prev.waypoints.filter(wp => wp.id !== id),
        }))
    }, [])

    // Calculate distance (Haversine)
    const calculateDistance = useCallback(() => {
        if (plan.waypoints.length < 2) return 0
        let total = 0
        for (let i = 1; i < plan.waypoints.length; i++) {
            const prev = plan.waypoints[i - 1]
            const curr = plan.waypoints[i]
            const R = 6371008.8 // Earth radius in meters
            const dLat = (curr.latitude - prev.latitude) * Math.PI / 180
            const dLon = (curr.longitude - prev.longitude) * Math.PI / 180
            const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(prev.latitude * Math.PI / 180) * Math.cos(curr.latitude * Math.PI / 180) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
            total += R * c
        }
        return total
    }, [plan.waypoints])

    // Calculate flight time
    const calculateFlightTime = useCallback(() => {
        const distance = calculateDistance()
        const holdTime = plan.waypoints.reduce((sum, wp) => sum + wp.holdTime, 0)
        return plan.cruiseSpeed > 0 ? (distance / plan.cruiseSpeed) + holdTime : holdTime
    }, [calculateDistance, plan.waypoints, plan.cruiseSpeed])

    // Export KMZ
    const exportKmz = useCallback(async () => {
        if (plan.waypoints.length < 2) {
            showToast('至少需要 2 个航点', 'error')
            return
        }

        setIsExporting(true)
        try {
            const result = await invoke<string>('generate_kmz', {
                name: plan.name,
                waypoints: plan.waypoints.map(wp => ({
                    latitude: wp.latitude,
                    longitude: wp.longitude,
                    altitude: wp.altitude,
                    speed: wp.speed,
                    holdTime: wp.holdTime,
                })),
                cruiseSpeed: plan.cruiseSpeed,
                cameraAngle: plan.cameraAngle,
            })
            setLastExportPath(result)
            showToast(`已导出: ${result}`, 'success')
        } catch (error) {
            showToast(`导出失败: ${error}`, 'error')
        } finally {
            setIsExporting(false)
        }
    }, [plan, showToast])

    const syncToRc2 = useCallback(async () => {
        if (plan.waypoints.length < 2) {
            showToast('至少需要 2 个航点', 'error')
            return
        }

        setIsSyncing(true)
        try {
            const result = await invoke<string>('sync_to_rc2', {
                name: plan.name,
                waypoints: plan.waypoints.map(wp => ({
                    latitude: wp.latitude,
                    longitude: wp.longitude,
                    altitude: wp.altitude,
                    speed: wp.speed,
                    holdTime: wp.holdTime,
                })),
                cruiseSpeed: plan.cruiseSpeed,
                cameraAngle: plan.cameraAngle,
            })
            showToast(result, 'success')
        } catch (error) {
            showToast(`同步失败: ${error}`, 'error')
        } finally {
            setIsSyncing(false)
        }
    }, [plan, showToast])

    const distance = calculateDistance()
    const flightTime = calculateFlightTime()
    const activeTileProvider = useMemo(() => tileProviders[tileProviderIndex], [tileProviderIndex])

    const handleTileError = useCallback(() => {
        if (tileFallbackLock.current) {
            return
        }

        tileFallbackLock.current = true

        if (tileProviderIndex < tileProviders.length - 1) {
            const nextProvider = tileProviders[tileProviderIndex + 1]
            setTileProviderIndex((current) => Math.min(current + 1, tileProviders.length - 1))
            showToast(`底图加载失败，切换到 ${nextProvider.name}`, 'error')
        } else {
            showToast('在线底图加载失败。仍可在空白区域点击添加航点。', 'error')
        }

        window.setTimeout(() => {
            tileFallbackLock.current = false
        }, 1000)
    }, [showToast, tileProviderIndex])

    return (
        <div className="app-container">
            {/* Sidebar */}
            <aside className="sidebar">
                <div className="sidebar-header">
                    <div className="hero-badge">Windows MVP</div>
                    <h1>DronePlan</h1>
                    <p>RC 2 航点规划与 KMZ 导出</p>
                </div>

                <div className="sidebar-content">
                    <div className="callout callout-warm">
                        <div className="callout-title">当前交付边界</div>
                        <div className="callout-text">
                            这版先解决现场交付：规划航点、导出 KMZ，或直接替换 Windows / microSD 上的占位任务文件。
                        </div>
                    </div>

                    {/* Plan Name */}
                    <div className="section">
                        <div className="section-title">飞行计划</div>
                        <div className="form-group">
                            <input
                                type="text"
                                className="form-input"
                                value={plan.name}
                                onChange={(e) => setPlan(prev => ({ ...prev, name: e.target.value }))}
                                placeholder="计划名称"
                            />
                        </div>
                    </div>

                    {/* Parameters */}
                    <div className="section">
                        <div className="section-title">全局参数</div>

                        <div className="slider-group">
                            <div className="slider-header">
                                <span className="slider-label">巡航速度</span>
                                <span className="slider-value">{plan.cruiseSpeed.toFixed(1)} m/s</span>
                            </div>
                            <input
                                type="range"
                                className="slider"
                                min="2"
                                max="25"
                                step="0.5"
                                value={plan.cruiseSpeed}
                                onChange={(e) => setPlan(prev => ({ ...prev, cruiseSpeed: parseFloat(e.target.value) }))}
                            />
                        </div>

                        <div className="slider-group">
                            <div className="slider-header">
                                <span className="slider-label">默认高度</span>
                                <span className="slider-value">{plan.maxAltitude} m</span>
                            </div>
                            <input
                                type="range"
                                className="slider"
                                min="20"
                                max="500"
                                step="5"
                                value={plan.maxAltitude}
                                onChange={(e) => setPlan(prev => ({ ...prev, maxAltitude: parseInt(e.target.value) }))}
                            />
                        </div>

                        <div className="slider-group">
                            <div className="slider-header">
                                <span className="slider-label">云台俯仰角</span>
                                <span className="slider-value">{plan.cameraAngle}°</span>
                            </div>
                            <input
                                type="range"
                                className="slider"
                                min="-90"
                                max="0"
                                step="5"
                                value={plan.cameraAngle}
                                onChange={(e) => setPlan(prev => ({ ...prev, cameraAngle: parseInt(e.target.value) }))}
                            />
                        </div>
                    </div>

                    {/* Waypoints */}
                    <div className="section">
                        <div className="section-title">航点 ({plan.waypoints.length})</div>

                        {plan.waypoints.length === 0 ? (
                            <div className="empty-state">
                                <div className="empty-state-icon">📍</div>
                                <div className="empty-state-title">还没有航点</div>
                                <div className="empty-state-text">点击地图添加航点</div>
                            </div>
                        ) : (
                            <ul className="waypoint-list">
                                {plan.waypoints.map((wp, index) => (
                                    <li key={wp.id} className="waypoint-item">
                                        <div className="waypoint-number">{index + 1}</div>
                                        <div className="waypoint-info">
                                            <div className="waypoint-coords">
                                                {wp.latitude.toFixed(5)}, {wp.longitude.toFixed(5)}
                                            </div>
                                            <div className="waypoint-alt">{wp.altitude}m</div>
                                        </div>
                                        <button
                                            className="waypoint-delete"
                                            onClick={() => removeWaypoint(wp.id)}
                                            title="删除航点"
                                        >
                                            ✕
                                        </button>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>

                    <div className="section">
                        <div className="section-title">RC 2 导入流程</div>
                        <ol className="workflow-list">
                            {importSteps.map((step) => (
                                <li key={step} className="workflow-item">
                                    {step}
                                </li>
                            ))}
                        </ol>
                    </div>

                    <div className="section">
                        <div className="section-title">实施注意</div>
                        <ul className="note-list">
                            {workflowNotes.map((note) => (
                                <li key={note} className="note-item">
                                    {note}
                                </li>
                            ))}
                        </ul>
                    </div>

                    {lastExportPath && (
                        <div className="section">
                            <div className="section-title">最近导出</div>
                            <div className="callout">
                                <div className="callout-title">KMZ 已生成</div>
                                <div className="callout-path">{lastExportPath}</div>
                            </div>
                        </div>
                    )}
                </div>

                {/* Footer with export buttons */}
                <div className="sidebar-footer">
                    <div className="btn-group">
                        <button
                            className="btn btn-primary btn-full"
                            onClick={syncToRc2}
                            disabled={plan.waypoints.length < 2 || isExporting || isSyncing}
                        >
                            {isSyncing ? '同步中...' : '同步到 RC 2'}
                        </button>
                    </div>
                    <div className="btn-group" style={{ marginTop: 8 }}>
                        <button
                            className="btn btn-secondary btn-full"
                            onClick={exportKmz}
                            disabled={plan.waypoints.length < 2 || isExporting || isSyncing}
                        >
                            {isExporting ? '导出中...' : '导出 KMZ'}
                        </button>
                    </div>
                    <div className="footer-hint">
                        先在 DJI Fly 刚创建一个占位任务，再点击“同步到 RC 2”。如果当前 Windows 环境下无法直连，则使用“导出 KMZ”改走 microSD。
                    </div>
                </div>
            </aside>

            {/* Map */}
            <div className="map-container">
                <div className="map-hint">
                    <div className="map-hint-title">如何操作</div>
                    <div className="map-hint-text">单击地图添加航点，滚轮缩放，按住拖动平移。</div>
                </div>
                <MapContainer
                    center={[39.9042, 116.4074]}
                    zoom={13}
                    style={{ height: '100%', width: '100%' }}
                >
                    <TileLayer
                        key={activeTileProvider.name}
                        attribution={activeTileProvider.attribution}
                        url={activeTileProvider.url}
                        eventHandlers={{ tileerror: handleTileError }}
                    />
                    <MapClickHandler onMapClick={handleMapClick} />

                    {/* Waypoint markers */}
                    {plan.waypoints.map((wp, index) => (
                        <Marker
                            key={wp.id}
                            position={[wp.latitude, wp.longitude]}
                            icon={waypointIcon(index)}
                        />
                    ))}

                    {/* Flight path polyline */}
                    {plan.waypoints.length >= 2 && (
                        <Polyline
                            positions={plan.waypoints.map(wp => [wp.latitude, wp.longitude])}
                            color="#0071e3"
                            weight={3}
                            opacity={0.8}
                        />
                    )}
                </MapContainer>

                {/* Status bar */}
                {plan.waypoints.length > 0 && (
                    <div className="status-bar">
                        <div className="status-item">
                            <span className="status-value">{plan.waypoints.length}</span>
                            <span className="status-label">航点</span>
                        </div>
                        <div className="status-item">
                            <span className="status-value">{(distance / 1000).toFixed(2)} km</span>
                            <span className="status-label">距离</span>
                        </div>
                        <div className="status-item">
                            <span className="status-value">{Math.floor(flightTime / 60)}:{String(Math.floor(flightTime % 60)).padStart(2, '0')}</span>
                            <span className="status-label">预计时间</span>
                        </div>
                    </div>
                )}
            </div>

            {/* Toast notification */}
            {toast && (
                <div className={`toast ${toast.type}`}>
                    {toast.message}
                </div>
            )}
        </div>
    )
}

export default App
