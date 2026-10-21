# 白场修正测试位流

## 最新独立发布：时序 / CDC 修复 A（2026-10-21）

烧录 `timing_closure_20261021_a/camera_timing_closure_20261021_a.bit`。已获用户同意合入隔离验证版修复；保留现有显示、跟踪和找回功能，修复 DDR 参考、复位释放及 CDC/I2C 时序。40 项仿真、Python 17 项通过；Setup/Hold WNS +0.116/+0.020 ns，STA 覆盖 98.49%，Slice 82.69%、ERAM 92/108、DSP 27/40。新生成而非旧文件改名，实板待验收，不自动烧录。见 [烧录和验收说明](timing_closure_20261021_a/README.md)。

## 历史独立发布：快速找回资源优化 A（2026-10-20）

烧录 `local_template_fast_resource_opt_20261020_a/camera_template_fast_resource_opt_20261020_a.bit`。保留快速找回全部功能、精度和时延，ERAM99→95、DSP29→27，Slice增加61至18300（86.26%）；不是所有资源都下降。35项仿真配置、Python17项与隔离实现通过，Setup/Hold WNS +0.136/+0.020ns，STA覆盖95.86%。实板待验收，旧文件未覆盖；不新增缩放适应。见[烧录说明](local_template_fast_resource_opt_20261020_a/README.md)。

## 历史独立发布：快速粗搜找回 A（2026-10-20）

烧录 `local_template_fast_reacquire_20261020_a/camera_template_fast_reacquire_20261020_a.bit`。新增缩小图粗搜、原分辨率三帧确认，旧慢速全画面/近邻兜底保留；720p静态仿真约0.617秒恢复，不保证实景秒级，不支持旋转/缩放。33项仿真配置、Python17项及隔离实现通过；Slice85.97%、ERAM99/108、DSP29/40，Setup/Hold WNS +0.252/+0.020ns，STA覆盖95.77%；实板待验收。详见[烧录说明](local_template_fast_reacquire_20261020_a/README.md)。下条为上一独立发布。

## 历史独立发布：分片全画面找回（2026-10-20）

烧录 `local_template_global_reacquire_20261020_a/camera_template_global_reacquire_20261020_a.bit`。保留初期邻域优先，再交替扫描局部/全画面，720p共3234个全局窗口；完整轮询理想约108秒另加确认，不是秒级检测，不含旋转/缩放。26项仿真配置、Python17项及隔离构建通过，Slice83.97%、ERAM71，Setup/Hold WNS=+0.179/+0.020ns，STA覆盖95.82%；新位流实板待验收。详见[烧录说明](local_template_global_reacquire_20261020_a/README.md)。

## 历史独立发布：近邻优先的扩大找回（2026-10-20）

烧录 `local_template_far_reacquire_20261020_a/camera_template_far_reacquire_20261020_a.bit`。最后位置/中央名义约±73个处理像素，每3个失败近邻窗口插入1个远邻；完整远邻轮询576帧（60fps理想条件约9.6秒另加确认），不是全画面。22项仿真配置、Python17项与隔离构建通过，Slice84.03%，ERAM71，Setup/Hold WNS=+0.316/+0.020ns，STA覆盖95.77%；新位流实板待验收，历史版本保留。详见[烧录说明](local_template_far_reacquire_20261020_a/README.md)。

## 历史独立发布：功能保持的资源优化（2026-10-20）

烧录 `local_template_resource_opt_20261020_a/camera_template_resource_opt_20261020_a.bit`。保留已实板验证扩展A的功能、范围、参数和时延；Slice89.35%→84.36%，LUT减少1363，ERAM多用5个至71。59011955周期对照、21项仿真配置、Python17项及隔离构建通过；Setup/Hold WNS=+0.337/+0.020ns，STA覆盖95.79%。新位流实板待验收，详见[烧录说明](local_template_resource_opt_20261020_a/README.md)。

## 历史独立发布：LOST分阶段邻域找回（2026-10-20）

烧录 `local_template_expanded_20261020_a/camera_template_expanded_reacquire_20261020_a.bit`。最后位置/中央两锚点逐帧扫描八方向邻域，总覆盖名义约±25个720p处理像素，3帧确认不变，不是全画面或旋转缩放适应。20项仿真配置、Python17项、隔离综合/路由通过，Setup/Hold WNS=+0.106/+0.020ns，STA覆盖96.20%，Slice89.35%余量紧；实板待验收。详见[烧录说明](local_template_expanded_20261020_a/README.md)。

## 历史独立发布：模板匹配RAM预取与连续累加（2026-10-20）

烧录 `local_template_sad_pipeline_20261020_a/camera_template_sad_pipeline_20261020_a.bit`。计算38602→13654时钟，原搜索范围、匹配门限和3帧自动找回不变，不提高帧率。19项仿真配置、Python17项、隔离综合/路由通过；Setup/Hold WNS=+0.176/+0.020ns，STA覆盖96.31%，实板待验收。不覆盖历史位流，详见[烧录说明](local_template_sad_pipeline_20261020_a/README.md)。

## 历史独立发布：最后位置/中央快速自动找回（2026-10-20）

烧录 `local_template_reacquire_20261020_a/camera_template_reacquire_20261020_a.bit`。保留原模板，LOST后交替搜索最后可靠位置和中央附近，连续3帧合格后由黄色VERIFY恢复绿色TRACK。不是全画面找回，不自动重学背景；按键及细步进跟踪保留。18项配置及扩展回归、综合/路由通过，Setup/Hold WNS=+0.197/+0.020ns，TNS/违例端点0，STA覆盖95.78%。详见[烧录说明](local_template_reacquire_20261020_a/README.md)。

## 历史独立发布：小幅移动模板跟踪优化（2026-10-20）

烧录 `local_template_fine_20261020_d/camera_template_fine_20261020_d.bit`。2像素粗搜、两候选峰1像素细化，每帧约±9像素；修正右下角计数，新增TPL的E/U/R/M诊断，R:1才是跨帧匹配通过。KEY3长按选定/解除、短按曝光，KEY2不变。全部回归及路由通过：Setup/Hold WNS=+0.231/+0.020ns，TNS/违例端点0，STA覆盖95.78%。Slice17528，LUT6=15746，REG15818，ERAM71/108，DSP27/40。实板待验收，未覆盖历史文件。详见[交付说明](local_template_fine_20261020_d/README.md)。

## 历史独立发布：中央选定与局部模板跟踪原型（2026-10-20）

烧录 `local_template_20261020_b/camera_local_template_20261020_b.bit`，不覆盖原best_result。中央64×64青框选择，KEY3长按锁定/解除，短按松开仍切曝光；KEY2原功能保留。TPL绿/橙/红表示TRACK/HOLD/LOST，FLAT表示纹理不足；未新增串口或数值坐标，旧C/X/Y/P仍属于颜色检测。局部搜索±32像素、8像素步进，不承诺任意运动/旋转缩放。Setup/Hold WNS=+0.225/+0.020ns，TNS与违例端点均0，STA覆盖95.79%；ERAM67/108、DSP27/40。详见[模板跟踪原型说明](../docs/LOCAL_TEMPLATE_TRACKING.md)，实际效果待实板验证。

## 历史独立发布：RAW 中心对齐锐化（2026-10-20）

烧录 `raw_centered_20261020_a/camera_raw_centered_20261020_a.bit`。该文件通过功能回归和隔离路由时序后生成，不覆盖原 `best_result`。上电锐化关闭，KEY2长按约1秒切RAW锐化，短按切模式，KEY3不变。Setup/Hold WNS=+0.129/+0.020ns，TNS与违例端点均0；STA覆盖95.79%，ERAM66/108、DSP27/40。详见 [修复及验证说明](../docs/RAW_CENTERED_PIPELINE.md)。下列10月19日条目为历史发布。

## 最新：RAW 显示直通恢复

`camera_raw_restore_20261019.bit`，2026-10-19 19:55:06 生成，已同步原 `best_result`。默认关闭新增的 2×2 显示降噪和暗部曲线，RAW/GRAY 不再经过这两步处理；曝光、白场、Logo/OSD、Canny 门限与 10 帧保持不变。本次不修复 Canny 内部细节，也不加入通用目标跟踪。

- 标准 SHA256：`9103D25C1E925028DA445D8D6A35C69886FC35CF729512A00366C709AADA75C0`。
- 压缩 SHA256：`D6081B62D4A785A417E52C8B8D7E99BFA53BD4928758DD303173958BA8D2B6B5`。
- Setup/Hold WNS +0.186/+0.020 ns，TNS=0；Slice 16324（76.94%），ERAM 56/108，DSP 24/40。
- 原目录 5 个普通文件已校验备份到 `best_result/backup_before_raw_restore_20261019_195529/`，包括用户自行构建版；旧标准位流 SHA256 为 `50AE9F2733015E01B6EA1A6A67A2049F2F508050D067521D55137FC0054888B8`。
- 详见 [RAW 恢复说明](../docs/RAW_RESTORE.md)。逐像素/功能仿真及最终时序通过，实际清晰度仍待烧录对比。未提交/推送 GitHub。

## 历史：Canny 轻度抑噪

`camera_canny_noise_light_20261019.bit`，2026-10-19 19:23:16 生成，已同步原 `best_result`。只轻调 Canny 弱门限为 48/64/68、强门限为 80/104/120；亮度修正版的曝光/增益保留，RAW/GRAY/COLOR 不变。仍不包含通用目标跟踪。

- 标准 SHA256：`6C3DEA523D9D1F1B583F702B913787212C17047A8465B94091649B73C9735E75`。
- 压缩 SHA256：`4D7AB24ACE3FB3C4AD8539C8E58AAD4CECF1BB3300FC8540317210B8051B7B51`。
- Setup/Hold WNS +0.053/+0.020 ns，TNS=0；Slice 16701（78.72%），ERAM 56/108，DSP 24/40。
- 旧版 5 个文件已逐个校验备份至 `best_result/backup_before_canny_noise_20261019_192328/`；旧标准位流哈希为 `C5FF9AE7B9551FFDEF5EE12370ACA4A8C05882D77F8471AD6768C7454A8EB230`，没有假定用户自行构建版与之前存档相同。
- 详见 [Canny 轻度抑噪](../docs/CANNY_NOISE_TUNING.md)。仿真与时序通过，实拍仍待确认，未提交/推送 GitHub。

## 历史：亮度修正（仍不包含通用目标跟踪）

`camera_brightness_fix_20261019.bit`，2026-10-19 18:55:47 生成，已同步原 `best_result`。恢复 AUTO 增益上限索引 176，并允许大片暗部/少量亮斑场景继续增亮；降噪、暗部曲线及手动四档保留。X/Y/P 仍是颜色检测结果。

- 标准 SHA256：`75D7AAB1659F26B9F145FB470039D8F33C035166D4A764218562E7BB8EF0F934`。
- 压缩 SHA256：`782FC1A2D4BDA0082DF239190E44A1C3451856488C8F38BDA79E4E60113AA782`。
- Setup/Hold WNS +0.130/+0.020 ns，TNS=0；Slice 16820（79.28%），ERAM 56/108，DSP 24/40。
- 替换前 5 个文件已校验备份至 `best_result/backup_before_brightness_fix_20261019_185606/`，包括用户后续自行构建的文件，未假定它们与 18:27 存档一致。
- 详见 [亮度修正](../docs/BRIGHTNESS_FIX.md)。实际亮度待烧录验证，未推送 GitHub。

## 历史：RAW / GRAY 画质优化

`camera_picture_quality_20261019.bit`，2026-10-19 18:27:55 生成，已同步原 `best_result/camera_to_dsi_display.bit`。平坦区边缘门控降噪、轻度暗部提亮；AUTO 增益控制上限 96（按当前表约 6×），手动四档不变。保留白场 V2、原版 Logo/OSD、颜色/Canny 和用户当前 HOLD=10。

- 标准 SHA256：`16A82ED23AB2466EBC5614DD58CB1D4BA4346AD7EF2F196A6123AFB4C9C4C6CE`。
- 压缩 SHA256：`9A61AA83C4D82DE22E6DDD7CC1AC21397DFAFA5216B11D4CA16A46F1388CB53F`。
- 最终 Setup/Hold WNS：+0.126/+0.020 ns，TNS=0、违规端点 0；Slice 16784（79.11%），LUT6 14680，ERAM 56/108，DSP 24/40；STA 覆盖率 95.96%，沿用原 SDC。
- 旧版 5 个普通文件已逐个校验备份至 `best_result/backup_before_picture_quality_20261019_182807/`；其中旧标准位流 SHA256 为 `7B8F90FC93C75AD6505514258DD256FC43BA986F720AD2D2896FF7698742F5EA`。
- 仿真及限制见 [画质优化说明](../docs/PICTURE_QUALITY.md)。未上板确认效果，未提交或推送 GitHub。

## 历史：颜色跟踪抗丢帧

当前交付：`camera_target_tracking_20261017.bit`（2026-10-17 20:20:10）。800 像素获取、400 像素保持；短暂漏检保留 4 帧，第 5 帧取消锁定；TRACK/HOLD/LOST 明确区分新测量与旧坐标，P 始终为实际计数。保留原 ROM Logo、白场 V2、边缘精修及原按键/曝光逻辑。

- 标准 SHA256：`573D02A2513EE3BFC66E46583367544CB447DA357190BBAABB4D22120929FE6C`。
- 压缩 SHA256：`E620A9994CCD24B78BB7E023B818F64AA31CFED8A5FC297D3182CB720C80A0F3`。
- Setup WNS +0.251 ns，Hold WNS +0.020 ns，TNS=0、违规端点 0；Slice 76.97%，ERAM 56/108，DSP 24/40。
- 标准/压缩位流、BID 和时序摘要已同步原 `best_result`；被替换的 19:44 文件及其他普通文件共 5 个完整备份在 `backup_before_target_tracking_20261017_202010/`。
- 验证、参数和信号语义见 [颜色跟踪优化](../docs/TARGET_TRACKING_STABILITY.md)。尚未上板验证；本次没有提交或推送 GitHub。

## 之前：直接使用安路例程原 ROM

之前交付：`camera_example_logo_20261017.bit`（2026-10-17 19:34:55）。直接使用 `lab_ex3_osd_SC520` 中的原版 `anlogic_logo_rom.v` 和原透明规则，不裁剪/量化；保留左上状态文字、白场 V2 和边缘精修。原 `best_result` 现为上述跟踪优化版。

- 标准 SHA256：`CD8D4F328904B4DB33A0358F4AD855B86C478A3BF4B2024CA85F593726BB91C7`。
- Setup WNS +0.213 ns，Hold WNS +0.020 ns，违规端点 0。
- 已同步标准/压缩位流、BID、时序摘要到原 `best_result`。
- 旧文件备份：`best_result/backup_before_example_logo_20261017_193455/`。
- 例程来源、原文件校验和仿真预览见 [原例程接入](../docs/EXAMPLE_LOGO.md)。实际显示仍待烧录确认。

## 之前：16 色安路 Logo 与状态文字

之前交付：`camera_logo_status_20261017.bit`（2026-10-17 19:13:48）。该版使用裁剪/16 色转换，现已由上述原例程 ROM 版替代。

- 标准 SHA256：`0F572D00E2BA6593E063233BE615E4EBD111766C6DA0D564BB7C31E8E98B3506`。
- Setup WNS +0.367 ns，Hold WNS +0.020 ns，违规端点 0；叠加和 720p 边缘回归通过。
- 已同步到原 `best_result/camera_to_dsi_display.bit`，标准/压缩文件、BID、时序摘要均更新。
- 旧文件备份：`best_result/backup_before_logo_osd_20261017_191348/`。
- 说明和仿真预览见 [Logo 与状态文字](../docs/LOGO_AND_STATUS_OSD.md)。实际画面待烧录确认。

## 之前：边缘去孤点与短断口连接

之前交付 `camera_edge_clean_link_20261017.bit`（2026-10-17 17:36:22），保留白场 V2，在边缘加粗前增加去无支撑小点簇和四方向 1～2 像素连接。原 `best_result` 现已更新为上述 Logo/文字版。

- 标准位流 SHA256：`A50301C6268C60E88D66B3825FDD630BA630201B0E85BC48F0FDE039CB297517`。
- Setup WNS +0.241 ns，Hold WNS +0.020 ns，违规端点 0；720p 四帧逐像素仿真通过。
- 原文件备份：`best_result/backup_before_edge_refine_20261017_173622/`。
- 使用方法：烧录原目录的 `camera_to_dsi_display.bit`，切到 CANNY 边缘模式，不用额外标定。
- 限制和完整验证见 [边缘清理与连接](../docs/EDGE_REFINEMENT.md)，实际效果待烧录确认。

## 白场 V2 历史验证文件

白场 V2 原验证文件为 `camera_whitefield_paper_v2_20261017.bit`（生成时间 15:55:01），原先同步到用户 `best_result/camera_to_dsi_display.bit`，该交付位置现已更新为上述边缘精修版。白场 V2 上电直接应用，不用长按、也不用再次摆白板做按键标定。白场 V2 替换前的更早文件仍保存在 `best_result/backup_before_paper_v2_20261017/`。

- SHA256：`59B133D52AA1F297AB0445A0F37D093AA52691A1200C702D3E366F46D5A33791`。
- 根据两张实拍白纸的残余色差重新计算，原 AWB/自动曝光逻辑不变。
- 最终 Setup WNS `+0.326 ns`，Hold WNS `+0.020 ns`，违规端点 0。
- 操作与限制见 [白纸残差补偿 V2](../docs/WHITE_FIELD_PAPER_V2.md)。这是待实板确认的版本，不宣称照片里的色偏已实际消除。

## 之前的经验补偿 V1

`camera_whitefield_easy_20261017.bit` 是旧经验补偿版，用户实拍已确认中央偏绿仍明显，已被上面的 V2 替代。

- 生成时间：2026-10-17 15:29:56；1,789,539 字节。
- SHA256：`1F2684AA4A030D7658C8D244086BA10846B292D8349CCC709D33B6B486CF242C`。
- 最终布线时序：Setup WNS `+0.326 ns`，Hold WNS `+0.020 ns`，违规端点 0。
- 说明：[免操作轻度空间补偿](../docs/WHITE_FIELD_SOFT_PRESET.md)。

以下保留之前自标定版的记录。该版标定前固定 AWB，可能呈现明显整体偏绿，不作为当前免操作方案的默认文件。

## 之前的自标定版本

文件：`camera_whitefield_selfcal_20261017.bit`

- 生成时间：2026-10-17 15:10:15（本机时间）。
- 目标器件：PH1P35MDG324，速度档 3；文件大小 1,789,539 字节。
- SHA256：`D5D03BA2AE4D5DDFDC3550DD0D863FE9667580175877D3260661392B26AC427E`。
- 配置：板上自标定开启、实时 LSC 开启、全局 AWB 固定单位增益，没有写入合成场景增益表。
- 最终布线时序：Setup WNS `+0.437 ns`，Hold WNS `+0.020 ns`，违规端点 0。

烧录后，用均匀照明的白板覆盖整个视场，长按 KEY2 两秒，保持白板直到右上角蓝条变绿，再移开白板观察。红条表示标定无效，调整曝光或光照后重试。上电先显示未标定图像，不会自动拿正常场景当白板。KEY3 调曝光会废弃旧系数，断电后也需重新标定。

操作和验证说明见 [板上白场自标定](../docs/WHITE_FIELD_SELF_CALIBRATION.md)。该位流已生成并通过仿真和工具时序检查，尚未由助手烧录或确认实板效果。原 `best_result` 未覆盖。
