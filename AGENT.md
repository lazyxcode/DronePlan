# DronePlan

## 当前定位

DronePlan 当前是一个 **Windows-first 的 DJI RC 2 航点规划与 KMZ 导出工具**。

当前仓库已经实现的目标：
- 在桌面端地图上手动添加航点
- 生成 DJI Fly 可导入的 KMZ/WPML 任务文件
- 在 Windows 下尝试直连 RC 2，同步覆盖最新占位 `.kmz`
- 保留导出 KMZ 和 microSD 兜底工作流

当前仓库没有实现的内容：
- 没有可用的 macOS 直连 RC 2 同步
- 没有 DJI SDK 直连方案
- 没有 Web 版本
- 没有移动端应用
- 没有单独的 AI 规划模块

## 已确认的产品边界

### RC 2 导入路径
- 当前主方案是 `规划 -> Windows 直连 RC 2 同步`
- 兜底方案是 `规划 -> 生成 KMZ -> microSD 导入 RC 2`
- 不再假设 RC 2 支持 ADB 直连
- 不再假设 macOS 能稳定访问 RC 2 的可写数据通道

### 平台策略
- `Windows`：当前唯一面向交付的平台
- `macOS`：仅保留开发和文档用途，不作为 RC 2 传输主平台

## 当前仓库结构

```text
DronePlan/
├── AGENT.md
├── Cargo.toml
├── crates/
│   └── droneplan-core/
│       ├── Cargo.toml
│       ├── examples/
│       │   └── generate_sample_kmz.rs
│       └── src/
│           ├── error.rs
│           ├── lib.rs
│           ├── geo/
│           ├── kmz/
│           └── models/
├── apps/
│   └── desktop/
│       ├── package.json
│       ├── src/
│       │   ├── App.tsx
│       │   ├── index.css
│       │   └── main.tsx
│       └── src-tauri/
│           ├── Cargo.toml
│           ├── build.rs
│           ├── src/
│           └── tauri.conf.json
├── docs/
│   ├── RC2_USB_Transfer.md
│   └── RC2_Windows_Import.md
└── .github/
    └── workflows/
        └── build-windows.yml
```

## 模块说明

### `crates/droneplan-core`
Rust 核心库，负责：
- 飞行计划数据模型
- 航点与测区模型
- 地理计算
- KMZ/WPML 生成

主要入口：
- `crates/droneplan-core/src/lib.rs`
- `crates/droneplan-core/src/models/`
- `crates/droneplan-core/src/kmz/`
- `crates/droneplan-core/src/geo/`

### `apps/desktop`
Tauri 2 + React 桌面应用，当前是实际交付入口。

前端负责：
- 地图交互
- 航点编辑
- 计划参数输入
- 调用 Tauri 命令

后端负责：
- 将前端输入转换为 `FlightPlan`
- 生成 KMZ
- 让用户选择文件路径保存
- 在 Windows 下调用本地 helper 同步到 RC 2

当前已实现的 Tauri 命令：
- `generate_kmz`
- `replace_placeholder_kmz`
- `sync_to_rc2`

对应文件：
- `apps/desktop/src/App.tsx`
- `apps/desktop/src-tauri/src/lib.rs`

## 文档说明

- `docs/RC2_USB_Transfer.md`
  记录 macOS 直连 RC 2 不可作为当前主方案的结论。

- `docs/RC2_Windows_Import.md`
  记录当前可执行的 Windows / microSD 导入流程。

## 当前开发原则

1. 先保证 `KMZ 文件正确可导入`
2. 先保证 `Windows 工作流可交付`
3. 不在当前阶段扩展到 Web / iOS / iPadOS
4. 不在当前阶段假设 DJI 会提供新的桌面同步接口
5. 文档必须描述“当前真实状态”，不要把愿景写成已实现能力

## 常用命令

```bash
# Rust core
cargo build -p droneplan-core
cargo test -p droneplan-core

# Desktop frontend
cd apps/desktop
npm install
npm run build
npm run tauri dev
npm run tauri build

# Desktop backend check
cd /Users/ac/Dev/aibox/app/DronePlan
cargo check -p droneplan-desktop
```

## 当前已知缺口

- Windows 直连同步仍是启发式策略，默认覆盖最近修改的占位 `.kmz`
- 测区自动生成航线尚未完成
- CI 的 Windows 构建工作流需要继续校正

## 许可证

仓库包元数据使用 `UNLICENSED`，实际仓库保护条款见 `LICENSE` 与 `NOTICE`。
