# AI德州扑克对决 - 前端应用

这是AI德州扑克对决的Flutter前端应用。该应用提供了流畅、美观的用户界面，让玩家能够与各种AI对手进行德州扑克比赛。

## 功能特性

- 美观的扑克牌和牌桌设计
- 实时游戏状态显示
- 流畅的玩家动作交互
- 多玩家支持
- WebSocket实时通信
- 响应式布局，适配不同设备

## 运行应用

### 前提条件

- 安装Flutter开发环境（3.0或更高版本）
- 确保已经启动后端服务器

### 步骤

1. 进入frontend目录
   ```
   cd frontend
   ```

2. 安装依赖
   ```
   flutter pub get
   ```

3. 启用Web支持（如果尚未启用）
   ```
   flutter config --enable-web
   ```

4. 运行应用
   - 在Chrome浏览器中运行
     ```
     flutter run -d chrome
     ```
   - 在其他设备上运行（需要连接设备）
     ```
     flutter run
     ```

## 使用指南

1. 首页
   - 输入您的玩家名称
   - 选择"创建新游戏"或输入游戏ID"加入游戏"

2. 游戏界面
   - 游戏状态显示在顶部
   - 社区牌和底池显示在中央
   - 玩家信息围绕牌桌布局
   - 操作面板在轮到您行动时出现在底部
   - 可以选择弃牌、让牌、跟注或加注

## 项目结构

- `lib/main.dart` - 应用入口
- `lib/theme/` - 应用主题和样式
- `lib/models/` - 数据模型
- `lib/services/` - 服务类，如WebSocket通信
- `lib/components/` - UI组件
- `lib/screens/` - 应用界面

## 自定义配置

- 修改WebSocket服务器地址：编辑 `lib/services/websocket_service.dart` 中的 `_baseUrl` 参数 