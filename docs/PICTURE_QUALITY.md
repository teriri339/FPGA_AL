# RAW / GRAY 画质优化（2026-10-19）

> 历史版本：用户反馈本页 18:27 版过暗，最新 [亮度修正](BRIGHTNESS_FIX.md) 已恢复 AUTO 原增益范围。本页 6× 上限、位流及报告仅属于上一版；当前 `best_result` 为亮度修正版。

本次只优化画面，不加入运动检测，不改变 Canny、颜色判定、坐标含义和 10 帧漏检保持。原版安路 Logo、状态文字、按键、白场 V2 保留。实际效果仍需烧录后在相同照明、机位下对比，仿真不是实拍效果保证。

## 实现

1. `hx_vision_pipeline.v` 新增显示支路的边缘门控 2×2 降噪。窗口为当前、左、上、左上 RGB；三个邻点的每个通道与当前点差值均不超过 24 才平均，否则保留当前像素。使用 `(四点和+2)>>2`，不会溢出。首行、首列和跨模式窗口旁路，不读取上一帧残留作为有效邻域。
2. RAW/GRAY 小幅提亮暗部：`v<64: v+floor(v/4)`；`64<=v<128: v+floor((128-v)/4)`；其余不变。黑点仍为 0，128～255 不变，最大提升 16。曲线单调非递减，不是 HDR，也不能恢复已经削顶的细节。
3. `ae_set.v` 将 AUTO 的增益控制索引上限从 176 收敛到 96。按工程自身 `SC520GainTbl.v` 映射，上限从约 32× 改为约 6×（并非索引除以 16）。先增加曝光，再增加增益的顺序保留；由手动高增益转入 AUTO 时每次下降 4，避免突然变暗。四个手动档位、曝光上下限和高光保护保留。

降噪和暗部曲线只进入 RAW/GRAY 显示，位于 Logo/OSD 之前；不改变输入像素参与的测光、颜色检测或 Canny。AUTO 上限属于传感器设置，会影响所有模式看到的采集图像。暗处可能不如原先最高增益那么亮，这是限制噪声的代价；需要补光时不能靠无限加增益替代。

维持原有三拍显示延迟，五路视频控制标志和坐标不变；因使用因果窗口，不需要整行延迟显示。平坦区平均具有轻微空间平滑，24 阈值以内的低对比细节仍可能变软；强边缘旁路不等于所有纹理完全无损。本次不尝试修复灰尘、离焦、压缩或拍屏带来的损失，不重新拟合白场表。

可用 `ENABLE_DISPLAY_DENOISE=0` / `ENABLE_SHADOW_LIFT=0` 分别关闭两个显示功能。默认均打开；RAW 现在是增强后的 RGB 显示，不再代表这一模块的逐像素直通，更不是 Bayer RAW10。

## 验证入口

```powershell
./tools/test_picture_quality.ps1
./tools/test_target_tracking.ps1 -HoldFrames 10
python -m unittest discover -s tests -p 'test_*.py'
```

画质测试使用独立整数模型检查四帧 1280×720、平坦区噪声、强亮暗/彩色边界、模式切换、DE 间断、首行首列、三拍控制对齐；对比增强与旁路实例的全部目标/测光输出以及 COLOR/CANNY 像素。原 Logo 测试支持 `QUALITY_ENABLE=1`，检查增强后底图、原 ROM 全 RGB/透明像素以及 OSD。

已通过的功能验证：

- `tb_picture_quality`：3,686,400 像素与独立整数模型一致；204,901 个平坦区样点的提亮后误差平方和由 2,844,967 降至 742,349，下降约 73.9%。这是确定性合成噪声测试，不能当作实板信噪比承诺。
- `tb_picture_ae`：四个手动档位、AUTO 高增益逐步回收、上下限、高光降低曝光、暗场恢复及复位通过。
- `tb_logo_osd`：关闭/打开画质增强各 983,040 像素通过；原 ROM RGB、透明底图及 OSD 不变。
- `tb_vision_edge_modes`：24,576 像素通过；增强实例与旁路实例的 COLOR/CANNY、统计、控制比较由画质测试覆盖。
- `tb_target_tracking HOLD=10`：89 次帧统计发布、820,224 像素通过，保持用户当前 10 帧设置。
- Python 测试 17 项通过。

最终源码复测日志位于 `D:/Downloads/qiansai/tmp/picture_quality_sim_20261019_b/` 和 `D:/Downloads/qiansai/tmp/picture_tracking_sim_20261019_b/`。构建隔离目录为 `D:/Downloads/qiansai/tmp/picture_quality_20261019_b/`，未删除或重用用户 TD 的运行目录。

第一轮 `_a` 构建发现 Canny/COLOR 显示 mux 被带入降噪半周期路径，最终 setup WNS 为 -2.591 ns，因此不交付该位流。修正为独立 RAW/GRAY 输入后重新综合、布线和全量复测；没有用放宽约束掩盖时序问题。

## 最终交付

2026-10-19 18:27:55（Asia/Shanghai）生成 `bitstreams/camera_picture_quality_20261019.bit`，与原 `reference_edge_project/td_project/camera_to_dsi_display_Runs/best_result/camera_to_dsi_display.bit` 哈希一致；压缩版、BID 和时序摘要也已同步。

| 最终已布线指标 | 结果 |
| --- | --- |
| Setup / Hold WNS | +0.126 / +0.020 ns |
| Setup / Hold TNS | 0 / 0 ns，违规端点 0 |
| STA coverage | 95.96%，原 SDC 未放宽 |
| Slice / LUT6 | 16784（79.11%）/ 14680（69.19%） |
| 寄存器 / ERAM / DSP | 14887 / 56 / 24 |
| 标准位流大小 | 1,789,539 字节 |

标准 SHA256：`16A82ED23AB2466EBC5614DD58CB1D4BA4346AD7EF2F196A6123AFB4C9C4C6CE`。

压缩 SHA256：`9A61AA83C4D82DE22E6DDD7CC1AC21397DFAFA5216B11D4CA16A46F1388CB53F`。

替换前 5 个文件完整备份在 `best_result/backup_before_picture_quality_20261019_182807/`，复制后逐个 SHA256 校验通过。旧标准位流 SHA256：`7B8F90FC93C75AD6505514258DD256FC43BA986F720AD2D2896FF7698742F5EA`。本次未提交/推送 GitHub，也未操作板卡。

烧录新版后先切 RAW，在与旧版相同的照明和机位下拍摄对比即可，不要求重新标定。注意 AUTO 需要等待若干帧稳定；限制高增益不会使暗处凭空获得更多光线。
