# Bug Report: HiStreamer MediaDemuxer Thread 异常退出导致 AVPlayer 暂停恢复后画面冻结

## 摘要
在 HarmonyOS 设备上使用 AVPlayer（底层 HiStreamer 引擎）播放特定编码格式的视频时，暂停后恢复播放会导致 MediaDemuxer 线程异常退出，画面冻结（时钟停滞），而 AVPlayer 状态仍报告 `playing`。同一设备上播放 HEVC 编码视频时，暂停恢复正常，问题不复现。

## 复现环境
- **设备**: HUAWEI VDE-AL10 (Pura 70 Pro), HarmonyOS 5.0
- **应用**: 自研播放器 io.movieclaw.HUAWEI，使用系统 AVPlayer API
- **播放模式**: HTTP 拉流直出（档位0，files/{id}/stream），AVPlayer + HiStreamer 引擎
- **SDK**: OpenHarmony SDK (DevEco Studio)

## 复现步骤
1. 将 H.264 + AAC 编码的 MKV 视频通过 HTTP 直出方式提供给 AVPlayer
2. 等待视频正常播放（画面+声音正常）
3. 调用 `avplayer.pause()` 暂停播放
4. 等待数秒
5. 调用 `avplayer.play()` 恢复播放

## 期望行为
暂停恢复后，视频画面和声音应正常继续播放。

## 实际行为
- 暂停恢复后画面冻结，声音停止
- AVPlayer 状态仍报告 `playing`（state=playing）
- `currentTime` 停滞不变（不再递增）
- 无 `error` 回调、无 `buffering` 回调
- 冻结持续，永不自动恢复

## 根因分析

### hilog 时间线（2026-11-21 03:07 冻结事故）

```
03:07:15.790  HiStreamer: SetInterruptState: 0          ← 用户暂停
03:08:00.074  HiStreamer: SetInterruptState: 1          ← 用户恢复
03:08:00.223  MediaDemuxer: (Stop(), 3117): Thread exit ← ⚠️ demuxer 线程异常退出
03:08:00.247  HiStreamer: (Close(), 327): session already canceled  ← 会话已取消
03:08:00.248  HiStreamer: (Close(), 327): session already canceled (×3)
```

**关键发现**：`SetInterruptState: 1`（恢复）后，`MediaDemuxer::Stop()` 被调用，demuxer 线程退出，导致后续无数据供给解码器，画面冻结。

### 编码格式相关性

| 视频编码 | 播放诊断 | HiStreamer 管线 | 暂停恢复 | 结果 |
|---------|---------|---------------|---------|------|
| H.264 + AAC | 直出 · 档位0 · avplayer | 解码管线 | 暂停→恢复 | ❌ 冻结 |
| HEVC + AAC | 直出 · 档位0 · avplayer | **直通管线**（HEVC可直通） | 暂停→恢复 | ✅ 正常 |

**同一设备、同一引擎、同一播放路径**，仅视频编码不同，暂停恢复行为截然不同。

播放诊断界面确认 HEVC 走直通管线：
```
播放引擎：avplayer · playing
本机解码：AVPlayer 系统调度
解码规格：3840 × 1600
容器 mp4 · 档位 0
视频编码 HEVC 可直通；音轨 chi AAC 2声道 可直通
```

### 推断的内部机制

HiStreamer 对不同编码格式选择不同管线：
- **HEVC**：硬件解码器支持直通（passthrough），demuxer 只拆容器不解码，暂停恢复时 demuxer 线程正常重启
- **H.264**：走解码管线，demuxer 参与更深入，`SetInterruptState(1)` 恢复时触发了 `MediaDemuxer::Stop()` → Thread exit，demuxer 未被重新创建/启动，导致数据流中断

这是 **HiStreamer 内部管线路由的 bug**，与视频编码格式直接相关。

## 影响范围
所有使用 AVPlayer + HiStreamer 播放 H.264 视频并执行暂停/恢复操作的场景均可能受影响，包括但不限于：
- 在线视频播放（HTTP 拉流）
- 本地视频播放（若走 HiStreamer 解码管线）
- 任何需要暂停/恢复的视频播放场景

## 临时规避方案
1. 使用 mpv（ffmpeg）替代 AVPlayer 播放 H.264 内容
2. 将视频转码为 HEVC 编码（走直通管线）
3. 检测到冻结后，销毁并重建 AVPlayer 实例

## 附加信息

### 正常播放时的 HiStreamer 日志（HEVC 直通管线）
```
HiStreamer: (SaveCacheBufferData(), 1246): HTTP CacheMediaBuffer full.
（持续刷，表示 demuxer 正常取数）
```

### 冻结时的 AVPlayer 状态
- state: `playing`
- currentTime: 恒定不变（如卡在 462556ms = 7:42.556）
- 无 error 回调
- 无 buffering 回调
- stallSampleIntervalMs: 2000

### 相关源码位置（推测）
- `foundation/multimedia/media_framework/services/engine/histreamer/`
- `MediaDemuxer::Stop()` at line 3117
- `HiStreamer::SetInterruptState()` at line 536
- `HiStreamer::Close()` at line 327

### 数据库佐证
- playback_metric 表中，所有 H.264 视频的播放记录出现 `abnormal_exit`，而 HEVC 视频为正常 `exited`
- 服务器端日志可见多次降档尝试（档0→1→2→3），档0/1/2 均因 AVPlayer 播放失败而中断，仅档3（ffmpeg全转码为H.264+AAC标准流）成功

## 标签
`HiStreamer` `AVPlayer` `MediaDemuxer` `pause-resume` `freeze` `H.264` `HarmonyOS` `media_framework`
