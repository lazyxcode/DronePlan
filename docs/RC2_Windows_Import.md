## RC 2 Windows Import Workflow

当前可交付路径：

1. 在 RC 2 的 DJI Fly 中先创建一个占位任务，确保遥控器端已经生成最新任务文件。
2. 在 DronePlan 中完成航点规划。
3. 优先使用桌面端的 `同步到 RC 2` 按钮：
   - Windows helper 会尝试检测 RC 2 设备。
   - 在 DJI Fly 任务目录里搜索最近修改的占位 `.kmz`。
   - 直接覆盖该任务文件。
4. 如果当前 Windows / 固件组合下无法直连同步，则退回 `导出 KMZ`。
5. 导出失败兜底仍然是 microSD 中转：
   - 先在 RC 2 文件管理器里把任务目录复制到 microSD。
   - 在 Windows 上替换 microSD 里的 `.kmz`。
   - 再回到 RC 2 文件管理器中覆盖原任务目录。

注意事项：

- 目前没有官方桌面到 RC 2 的同步 API。
- 当前直连同步依赖 Windows 本地 helper 访问 MTP/WPD 设备，不依赖 DJI Windows SDK。
- 同步策略默认覆盖“最近修改的占位 `.kmz`”，因此实际使用前应先在 DJI Fly 中刚创建一个占位任务。
- 当 RC 2 固件或 Windows 文件访问行为变化时，应优先保留“导出 KMZ + microSD 中转”这条兜底路径。
