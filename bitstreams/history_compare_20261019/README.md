# 历史画质 A/B 对照

仅用于诊断，不替换当前工程或 best_result。

- A_current_20261019.bit：本次对照开始时保存的当前 best_result 快照。
- B_history_a7676fb_20261019.bit：10 月 16 日 a7676fb 历史源码隔离重建版。

固定机位、光照、镜头和采集设置。先烧 A，复位后保持 RAW，从 AUTO 按 KEY3 两次切到 EXP1，拍照；再烧 B，设置相同 EXP1 后拍照。若太暗，两版同时使用 EXP2。先比较 RAW，不以 Canny 或手机照片作为同源画质基准。B 没有后来新增的 Logo 属于预期。测试结束可烧 A 恢复当前版。

B 的历史设计源码 216 文件校验未修改；RAW/GRAY 仿真通过；Setup WNS 256ps、Hold WNS 20ps、TNS 均为 0。画质是否改善需要实拍确认。详细说明见仓库 docs/HISTORY_CAMERA_COMPARISON.md。
