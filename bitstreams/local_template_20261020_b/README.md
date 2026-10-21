# 中央选定与局部模板跟踪原型

烧录 camera_local_template_20261020_b.bit，不是原 best_result 文件。无需额外接线。

1. RAW/GRAY中央青色64×64框为选择区，TPL: READY。
2. 将独特、有纹理的目标区域对准中央框，稳住相机，单独长按KEY3约1秒，回RAW并学习；TPL: TRACK绿框表示已锁定。
3. 缓慢平移相机观察跟随。HOLD橙框保留最后可靠位置，连续16次失败进入LOST红框；FLAT紫框表示选区缺乏纹理。
4. 锁定时再长按KEY3解除回READY，再长按重新选定；LOST/FLAT时长按可直接重选。

KEY3短按松开仍切曝光，长按不切曝光档位；AUTO时原AE继续工作。KEY2原短按切模式/长按RAW锐化不变。请看第三行TPL状态；旧C/X/Y/P与顶部原TRACK/LOST属于颜色跟踪，未改成模板坐标。未新增串口或数值坐标输出。

搜索范围约±32像素，8像素步进，模板固定；不承诺大幅晃动、旋转缩放、遮挡后全局找回。第一版需实板验证，不是任意物体识别。

综合、功能回归、最终路由时序通过后才生成。Setup/Hold WNS=+0.225/+0.020ns，TNS/违例端点均0；STA覆盖95.79%。Slice16934，ERAM67/108，DSP27/40。原best_result、历史位流均未覆盖，未提交/推送。

标准SHA256：CD7469B8EFC8ADA4B78113F96DCB1B699C02CF393326145E44DC1A320FB94040。

压缩SHA256：0D9E12A46C1D3759501C52F6F7D6C9DD75B11C5F9047ED79CD9C4F68ACE79F39。

完整说明与验证记录见仓库 docs/LOCAL_TEMPLATE_TRACKING.md。
