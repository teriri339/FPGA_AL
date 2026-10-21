# RAW 中心对齐锐化修复版

烧录本目录 camera_raw_centered_20261020_a.bit，不是原 best_result 中的文件。

上电RAW原图、锐化关闭；KEY2长按约1秒切RAW锐化，开启显示SHARP；短按松开切模式；KEY3原曝光功能不变。中心对齐、四边保留，所有模式/控制信号固定延迟，OSD/Logo后叠加。默认门限6、最大增量±8、超过门限后半增益。只改善观感，不恢复失焦或远处采样不足的细节。

AP E是最后完整成功曝光写入控制值；A/D为0x3e09/0x3e06/0x3e07十六进制原始字节，不是增益倍数。OK仅指I2C完成且未观察到ACK错误，不是寄存器读回；ERR保留最后成功记录，不保证传感器仍保持该值。

综合、路由、相关功能回归通过后才生成。Setup/Hold WNS=+0.129/+0.020ns，TNS和违例端点均0，STA覆盖率95.79%。Slice16610，ERAM66/108，DSP27/40。原best_result和历史位流未覆盖，未提交/推送。

标准SHA256：78B5AE0A30CA9D917275FA6D9D6AF8B50815A6B1D142EEF43479C4353ABB26CA。

压缩SHA256：C73541CF9EB6AB69F89BF4A94AAA10F4B9895E07C870760C3FB28C5FC55B3AFE。

详见仓库 docs/RAW_CENTERED_PIPELINE.md；本目录附最终报告及源哈希清单。实拍效果仍需同曝光、同机位开关对照。
