## RC 2 USB Transfer Status

结论：

- macOS 直连 RC 2 的 ADB 会话在当前官方固件下不可用，诊断结果稳定表现为 `offline`。
- DJI 官方已明确说明：RC 2 没有官方桌面同步 API，ADB 对标准用户受限。
- 因此本项目不再把 macOS USB 直连作为主路径。

当前主路径：

1. 使用 DronePlan 规划航点并导出 `.kmz`。
2. 在 Windows 上完成 RC 2 文件替换，或使用 microSD 中转。

执行细节见：

- `docs/RC2_Windows_Import.md`
