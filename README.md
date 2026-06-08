# IMUNavigator

[License: MIT](LICENSE) | Platform: iOS 16.0+ | Swift 5.9

[English Version](#english-version) | [中文版](#中文版)

---

<a id="english-version"></a>
## English Version

An advanced iOS sensor fusion engine integrating ARKit (VIO), Pedestrian Dead Reckoning (PDR), and RoNIN Neural Inertial Navigation. IMUNavigator provides a robust, real-time trajectory plotting and spatial alignment laboratory.

### Core Features

* Cascade Sensor Fusion Engine: Seamlessly integrates Visual Inertial Odometry (ARKit), PDR, and Neural Network Dead Reckoning (RoNIN) for stable tracking.
* Blind Mode (Pure IMU): Works entirely without camera input, relying solely on PDR and Neural Dead Reckoning with strict spatial alignment.
* Real-time Trajectory Canvas: Auto-scaling bounds and live rendering of your moving path.
* ZUPT (Zero Velocity Update): Intelligently detects physical stationary states to eliminate neural network drift.
* Spatial Alignment Lab: Real-time velocity vector alignment (Auto Yaw) and manual calibration for pure IMU modes.
* Dynamic Drift Compensation: Independent X/Y axis damping controls and manual drift compensation.
* Live Activities & Background Mode: Track your metrics from the lock screen and continue logging in the background.

### Technology Stack

* Language: Swift
* UI Framework: SwiftUI & Canvas
* Sensors & Core API: CoreMotion, ARKit, CoreLocation
* Machine Learning: CoreML (RoNIN implementation)

### Installation

1. Clone the repository:
   git clone https://github.com/RayGA17/IMUNavigator.git
2. Open IMUNavigator.xcodeproj in Xcode.
3. Select your physical iOS device.
4. Build and Run.

### License
This project is licensed under the MIT License.

---

<a id="中文版"></a>
## 中文版

一款先进的 iOS 传感器融合引擎，深度集成了 ARKit 视觉惯性里程计 (VIO)、行人航位推算 (PDR) 以及 RoNIN 神经网络惯性导航技术。IMUNavigator 提供了强大的实时轨迹绘制与空间对齐实验功能。

### 核心功能

* 级联传感器融合引擎: 无缝集成视觉惯性导航 (ARKit)、PDR 和神经网络航位推算 (RoNIN)，提供高稳定性的追踪。
* 盲推模式 (纯 IMU): 完全脱离摄像头输入，仅依靠 PDR 和神经网络运行，并支持严格的空间对齐。
* 实时轨迹画布: 支持包围盒自动缩放机制，实时渲染平滑的运动轨迹。
* 零速修正 (ZUPT): 智能检测物理静止状态，彻底消除神经网络的静态漂移幻觉。
* 空间对齐实验室: 支持基于实时速度矢量的自动偏航角对齐 (Auto Yaw) 和纯 IMU 模式下的手动校准补偿。
* 动态漂移补偿: 提供独立的 X 轴/Y 轴阻尼控制与手动漂移常数补偿。
* 实时活动与后台模式: 支持锁屏灵动岛 (Live Activities) 数据监控与纯后台持续记录。

### 技术栈

* 开发语言: Swift
* UI 框架: SwiftUI 与原生 Canvas 渲染
* 底层框架: CoreMotion, ARKit, CoreLocation
* 机器学习: CoreML (基于 RoNIN 架构的模型部署)

### 安装指南

1. 克隆本仓库到本地:
   git clone https://github.com/RayGA17/IMUNavigator.git
2. 在 Xcode 中打开 IMUNavigator.xcodeproj 文件。
3. 选择你的 iOS 真机设备。
4. 编译并运行。

### 开源协议
本项目基于 MIT 协议开源。
