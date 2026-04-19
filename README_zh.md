# Handheld Controller (跨平台机器狗控制终端)

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?style=flat-square&logo=flutter)](https://flutter.dev/)
![Tested Platforms](https://img.shields.io/badge/Tested-Android%20%7C%20Windows-success?style=flat-square)
![Pending Platforms](https://img.shields.io/badge/Pending-Linux%20%7C%20macOS%20%7C%20iOS-lightgrey?style=flat-square)
[![License](https://img.shields.io/badge/License-CC%20BY--NC%204.0-red.svg)](https://creativecommons.org/licenses/by-nc/4.0/deed.zh-hans)

🌐 **[English](https://github.com/abrahamliu00/handheld_controller/blob/main/README.md)** | **[简体中文](https://github.com/abrahamliu00/handheld_controller/blob/main/README_zh.md)**

本项目是一个基于 Flutter 开发的机器狗上位机图传与控制终端。
通过 RTSP 协议拉取视频流，并利用 UDP 协议向目标 IP 发送控制指令。接收端 ROS 包见：[retroid_teleop](https://github.com/abrahamliu00/retroid_teleop)。

![Main Interface](./img/Main_Interface_zh.png)

## 📌 平台支持

本代码逻辑已做跨平台隔离，实际测试情况与各平台的系统接口限制如下：

| 平台          | 测试状态       | 输入方式           | 解码引擎        | 备注与系统限制                                           |
|:------------|:-----------|:---------------|:------------|:--------------------------------------------------|
| **Android** | ✅&nbsp;已验证 | 物理手柄 / 触屏      | `media_kit` | 适配 Retroid Pocket 4 专属底层广播通道。**支持应用内拉起 WiFi 设置**。 |
| **Windows** | ✅&nbsp;已验证 | 键盘 (WASD) / 鼠标 | `media_kit` | 自动映射 W/A/S/D。**不支持应用内跳转 WiFi 设置**。                |
| **Linux**   | ⏳&nbsp;待测试 | 键盘 (WASD) / 鼠标 | `media_kit` | 需预装 `libmpv`。**不支持应用内跳转 WiFi 设置**。                |
| **macOS**   | ⏳&nbsp;待测试 | 键盘 (WASD) / 鼠标 | `media_kit` | 未实机验证。**不支持应用内跳转 WiFi 设置**。                       |
| **iOS**     | ⏳&nbsp;待测试 | 触屏             | `media_kit` | 需声明本地网络权限。**不支持应用内跳转 WiFi 设置**。                   |

## 🛠️ 网络拓扑要求

系统网络要求如下：
- **默认环境**：建议控制端与被控端处于同一局域网下。
- **跨网段/外网控制**：代码未限制必须处于同一子网。只要目标 IP 网络可达（如 VPN 组网或端口映射），代码可直接向对应的广域网 IP 发送数据。

## 🔌 UDP 通信协议与数据帧

控制指令通过 UDP 发送。数据采用 **小端序**。
- **默认目标 IP**：`192.168.2.129`
- **默认目标端口**：`12121`
控制端每次发送固定长度的 **42 Bytes** 数据包，接收端通过 `recvfrom` 接收并解析。

| 偏移量 (Byte) | 类型       | 描述            | 数据处理逻辑                                                 |
|:-----------|:---------|:--------------|:-------------------------------------------------------|
| `0 - 1`    | `UInt8`  | 帧头标志          | 固定为 `0x55 0x66`                                        |
| `2`        | `UInt8`  | 保留位           | `0x00`                                                 |
| `3 - 4`    | `UInt16` | 数据体长度         | `32`                                                   |
| `5 - 6`    | `UInt16` | 预留            | `0`                                                    |
| `7`        | `UInt8`  | 协议版本/标志       | `0x01`                                                 |
| `8 - 9`    | `UInt16` | CRC 校验和       | Byte 10 到 Byte 41 的字节累加和                               |
| `10 - 23`  | `-`      | 保留位           | 默认为空 / 0                                               |
| `24 - 25`  | `Int16`  | 软急停 / 实体 B 键  | 按下状态为 `1`，释放为 `0`                                      |
| `26 - 29`  | `-`      | 保留位           | 默认为空 / 0                                               |
| `30 - 31`  | `Int16`  | `LX` (左摇杆X轴)  | 平移：范围 `[-1.0, 1.0]`，传输值为 `LX * 1000`                   |
| `32 - 33`  | `Int16`  | `LY` (左摇杆Y轴)  | 进退：范围 `[-1.0, 1.0]`，传输值为 `LY * 1000`                   |
| `34 - 35`  | `Int16`  | `RX` (右摇杆X轴)  | 转向：范围 `[-1.0, 1.0]`，传输值为 `RX * 1570` (对应极限 1.57 rad/s) |
| `36 - 37`  | `Int16`  | `RY` (右摇杆Y轴)  | 备用：范围 `[-1.0, 1.0]`，传输值为 `RY * 1000`                   |
| `38 - 41`  | `-`      | 尾部保留          | 默认为空 / 0                                               |

## 📦 快速开始

**1. 获取代码及依赖**

克隆仓库：
```bash
git clone https://github.com/abrahamliu00/handheld_controller.git
```
进入目录：
```bash
cd handheld_controller 
```
获取 Flutter 依赖：
```bash
flutter pub get
```

**2. 构建相应平台的程序**

构建 Android APK：
```bash
flutter build apk --release
```
构建 Windows 桌面版：
```bash
flutter build windows --release
```
## 🙏 致谢

本项目底层摇杆交互逻辑及部分架构实现参考并衍生自以下开源项目。特别感谢相关团队及开发者的开源贡献：

- **[DeepRoboticsLab/gamepad](https://github.com/DeepRoboticsLab/gamepad)**

详细许可说明请参阅该项目原仓库的 LICENSE 文件。

## 📄 许可证 (License)

本项目采用 **[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.zh-hans)** (知识共享署名-非商业性使用 4.0 国际许可协议) 进行开源。

**核心条款限制：**
- 允许自由分享、修改和分发本代码用于学术研究与个人学习。
- **最终项目代码严禁用于任何商业目的或盈利行为**。
- 必须保留原作者的署名信息。