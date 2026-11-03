"""Build the editable embedded-systems competition report from verified project notes."""

from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Cm, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "嵌赛项目报告.docx"


def set_font(style, size, bold=False):
    style.font.name = "宋体"
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor(0, 0, 0)
    style._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")


def shade(cell, color):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), color)
    tc_pr.append(shd)


def borders(cell):
    tc_pr = cell._tc.get_or_add_tcPr()
    el = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        b = OxmlElement(f"w:{edge}")
        b.set(qn("w:val"), "single")
        b.set(qn("w:sz"), "4")
        b.set(qn("w:color"), "D9D9D9")
        el.append(b)
    tc_pr.append(el)


def cell_margin(cell, top=100, start=120, bottom=100, end=120):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    margins = tc_pr.first_child_found_in("w:tcMar")
    if margins is None:
        margins = OxmlElement("w:tcMar")
        tc_pr.append(margins)
    for tag, val in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        e = OxmlElement(f"w:{tag}")
        e.set(qn("w:w"), str(val))
        e.set(qn("w:type"), "dxa")
        margins.append(e)


def para(doc, text="", *, bold_lead=None, keep=False):
    p = doc.add_paragraph(style="Normal")
    if bold_lead and text.startswith(bold_lead):
        p.add_run(bold_lead).bold = True
        p.add_run(text[len(bold_lead):])
    else:
        p.add_run(text)
    p.paragraph_format.keep_with_next = keep
    return p


def head(doc, title, level=1):
    p = doc.add_heading(title, level=level)
    if title == "2 系统总体方案":
        p.paragraph_format.page_break_before = True
    return p


def table(doc, heads, rows, widths=None):
    t = doc.add_table(rows=1, cols=len(heads))
    t.autofit = False
    if widths:
        for i, w in enumerate(widths):
            t.columns[i].width = Cm(w)
    for i, value in enumerate(heads):
        c = t.rows[0].cells[i]
        c.text = value
        shade(c, "E8EEF4")
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        borders(c)
        cell_margin(c)
        for p in c.paragraphs:
            for run in p.runs:
                run.bold = True
    for idx, row in enumerate(rows):
        cells = t.add_row().cells
        for i, value in enumerate(row):
            c = cells[i]
            c.text = str(value)
            if idx % 2:
                shade(c, "F8FAFC")
            c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            borders(c)
            cell_margin(c)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)
    return t


def figure(doc, number, title, instruction, height=3.1):
    t = doc.add_table(rows=1, cols=1)
    t.autofit = False
    c = t.cell(0, 0)
    c.text = f"图片预留位置\n{instruction}"
    c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    c.width = Cm(16.0)
    t.rows[0].height = Cm(height)
    borders(c)
    cell_margin(c, 160, 150, 160, 150)
    for p in c.paragraphs:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2)
        for run in p.runs:
            run.font.color.rgb = RGBColor(90, 90, 90)
            run.font.size = Pt(10)
    cap = doc.add_paragraph(f"图 {number}  {title}", style="Caption")
    cap.paragraph_format.keep_with_next = False
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    return t


doc = Document()
sec = doc.sections[0]
sec.page_width = Cm(21.59)
sec.page_height = Cm(27.94)
sec.top_margin = Cm(2.0)
sec.bottom_margin = Cm(1.8)
sec.left_margin = Cm(2.35)
sec.right_margin = Cm(2.35)
sec.header_distance = Cm(1.0)
sec.footer_distance = Cm(0.9)

styles = doc.styles
set_font(styles["Normal"], 10.5)
styles["Normal"].paragraph_format.line_spacing = 1.23
styles["Normal"].paragraph_format.space_after = Pt(6)
for name, size, before, after in (("Title", 23, 0, 16), ("Heading 1", 15, 17, 9), ("Heading 2", 12, 12, 6), ("Caption", 9.5, 5, 11)):
    st = styles[name]
    set_font(st, size, name != "Caption")
    st.paragraph_format.space_before = Pt(before)
    st.paragraph_format.space_after = Pt(after)
    st.paragraph_format.keep_with_next = name != "Caption"

header = sec.header.paragraphs[0]
header.text = "基于 FPGA 的实时视觉处理与动态目标跟踪系统"
header.alignment = WD_ALIGN_PARAGRAPH.RIGHT
for run in header.runs:
    run.font.size = Pt(8)
    run.font.color.rgb = RGBColor(90, 90, 90)
footer = sec.footer.paragraphs[0]
footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
footer.add_run("嵌入式竞赛项目报告  ·  ")
field = OxmlElement("w:fldSimple")
field.set(qn("w:instr"), "PAGE")
footer._p.append(field)
for run in footer.runs:
    run.font.size = Pt(8)

p = doc.add_paragraph(style="Title")
p.add_run("基于 FPGA 的实时视觉处理与动态目标跟踪系统")
p = doc.add_paragraph("嵌入式竞赛项目报告")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True
    run.font.size = Pt(15)
p = doc.add_paragraph("工程与仿真整理稿  ·  2026 年 11 月 3 日")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_after = Pt(20)

table(doc, ["申报信息", "待填写内容"], [
    ("参赛学校及队伍", "【填写学校、队伍名称】"),
    ("项目组成员", "【填写成员姓名及分工】"),
    ("指导教师", "【填写姓名】"),
    ("竞赛组别", "【按实际赛项填写】"),
], [4.2, 12.0])

head(doc, "摘要")
para(doc, "本项目面向摄像头实时视频处理与动态目标跟随演示，基于 FPGA 构建从 MIPI CSI-2 图像输入、RAW10 解码、ISP 处理、DDR 帧缓存到 HDMI 显示的完整链路。系统提供 RAW、GRAY 和 CANNY 三种显示模式；GRAY 模式在灰度图上叠加红色边缘轮廓，跟踪模式在目标锁定时绘制目标框。用户通过按键切换模式、调整曝光并选取目标。为改善短时跟丢，跟踪器引入运动预测、扩大局部搜索、十帧失配保持、全局重捕获以及固定初始模板与谨慎更新的短期模板。现有稳定版本已获上板正常显示反馈；最新双模板改动已通过部分功能仿真，最终时序和实物表现仍待复验。本报告按工程事实、仿真结果和待验证项目分别陈述，并预留实物与显示截图位置。")
para(doc, "关键词：FPGA；MIPI CSI-2；实时图像处理；边缘检测；模板跟踪；HDMI")

head(doc, "1 项目背景与目标")
para(doc, "视频图像任务常同时要求连续采集、低延迟显示和稳定跟踪。本项目以 FPGA 流水线处理为主，重点解决摄像头到显示器的稳定传输、图像模式切换以及目标短时丢失后的恢复。竞赛演示目标是：在 HDMI 屏幕上展示实时画面和边缘信息，使用按键完成模式与曝光控制，并在目标移动时显示可跟随的目标框。")
para(doc, "项目的性能评价以画面持续更新、模式响应、目标位置误差、跟踪连续性、重捕获能力和实现时序为依据。本文不把传感器配置帧率等同于实测端到端帧率，也不把仿真通过等同于上板验证。")

head(doc, "2 系统总体方案")
para(doc, "系统的数据路径为 SC520 系列摄像头输出 MIPI CSI-2 RAW10 数据，经接收与解包后进入 ISP；视频帧经 DDR 缓存，再由显示流水线完成模式处理、状态文字和目标框叠加，最终以 RGB888 送往 1280×720 HDMI 显示。控制路径由按键、曝光状态机与跟踪器组成。")
table(doc, ["模块", "作用", "工程实现要点"], [
    ("摄像头与输入", "采集 1280×720 视频", "SC520/SC520CS，双 Lane MIPI CSI-2，RAW10"),
    ("ISP 与缓存", "恢复彩色画面并跨时钟域缓存", "去马赛克、白平衡、DDR 帧缓存"),
    ("显示处理", "三种显示模式和 OSD", "RAW / GRAY / CANNY，RGB888 HDMI 输出"),
    ("动态跟踪", "目标选取、搜索、恢复", "64 点模板、预测、双模板与状态机"),
], [3.1, 4.9, 8.2])
figure(doc, 1, "系统结构框图", "插入摄像头 → MIPI 接收 → ISP → DDR → 显示处理 / 跟踪 → HDMI 的正式框图", 3.3)
figure(doc, 2, "开发板与摄像头实物连接", "插入开发板、摄像头、HDMI 显示器和按键位置的实拍照片", 3.1)

head(doc, "3 硬件链路与工程实现")
head(doc, "3.1 视频输入与显示", 2)
para(doc, "工程采用安陆 PH1P35MDG324 系列 FPGA，顶层为 design_top_wrapper，工程入口为 reference_edge_project/td_project/camera_to_dsi_display.al。摄像头配置为 1280×720、60 fps 输入规格；该数值属于配置目标，实际端到端帧率需要上板测量。HDMI 显示活动区为 1280×720。RAW 显示模式使用 ISP 后的彩色 RGB 画面，名称并非指直接显示 Bayer 原始像素。")
head(doc, "3.2 时钟、缓存与流水线", 2)
para(doc, "摄像头像素流、DDR 帧缓存和 HDMI 显示分别位于对应的数据与时钟链路。工程使用同步控制与流水线对齐，使显示有效信号、像素坐标、模式结果和 OSD 覆盖同一像素。对行缓存和模板采样优先使用 FPGA 片内 RAM，避免全帧片内存储；DDR 承担帧级缓存。工程的主参考时钟为 50 MHz，具体派生时钟以工程约束及实现报告为准。")
para(doc, "时序是功能成立的前提。2026 年 10 月 31 日的运动预测版本曾因复位恢复路径出现建立时序违例，调整布局种子后该版本实现报告显示建立余量 +0.104 ns、保持余量 +0.020 ns、违例为零。此结果只对应当时版本，不能移用为当前双模板改动的时序结论。")

head(doc, "4 图像处理与人机交互")
head(doc, "4.1 显示模式", 2)
para(doc, "KEY2 短按依次切换 RAW、GRAY、CANNY。RAW 显示 ISP 彩色画面；GRAY 将画面转换为灰度，并用红色标记与左侧或上侧像素亮度差达到阈值的轮廓点，当前阈值为 32；CANNY 使用平滑、梯度、非极大值抑制及边缘连接等处理生成轮廓视图。COLOR 模式已从切换序列中移除。GRAY 的红线属于方向差分轮廓，不应表述为完整 Canny 算法结果。")
para(doc, "KEY2 长按控制 RAW 锐化开关。KEY3 短按循环曝光档位，长按约一秒选取或取消中央目标。KEY1 用于复位。屏幕状态文字显示模式与相关控制状态；按键定义应在最终实物演示中逐项核对。")
figure(doc, 3, "RAW GRAY 与 CANNY 模式对比", "插入同一场景下三张真实屏幕照片，分别标注模式名称；GRAY 图需清晰显示红色轮廓", 3.3)

head(doc, "5 动态目标跟踪算法")
head(doc, "5.1 目标选取与特征匹配", 2)
para(doc, "用户长按 KEY3 后，以画面中央附近为初始目标建立 64×64 区域模板，并在区域内采集 8×8 个灰度样本。每个候选位置计算样本相对均值与模板相对均值之间的绝对差之和，以减弱整体亮度变化带来的影响。局部搜索半径为 12 像素，并结合上一帧速度预测搜索中心。显示框边长为 80 像素，只在 TRACK 状态绘制。")
para(doc, "匹配代价可写为 D = Σ |(Pᵢ − P̄) − (Tᵢ − T̄)|，其中 Pᵢ 是候选位置的采样灰度，Tᵢ 是模板采样灰度。该式描述灰度平移不变的零均值 SAD；最佳位置仍需通过误差和候选区分度门限，不能仅凭最小代价直接宣告锁定。")
head(doc, "5.2 预测、失配保持与重捕获", 2)
para(doc, "运动预测根据目标位置变化估计下一帧中心，速度限制在每帧 ±8 像素范围内。短时匹配失败时进入 HOLD，保留最近方向尝试恢复；连续失配达到十帧门限后进入 LOST，并通过粗到细的候选搜索与 VERIFY 确认重新捕获。这样可以减轻目标跨越小搜索窗口造成的直接丢失，但对突然大位移和相似背景仍有边界。")
head(doc, "5.3 固定模板与短期模板", 2)
para(doc, "初始模板在用户选取目标后冻结，提供长期参照；短期模板用于 TRACK 期间适应有限的外观渐变。只有连续三帧满足可靠性要求才允许更新：平均匹配误差不超过 8，最佳候选与其他独立候选的分数差至少 128，新样本相对初始模板的平均误差不超过 24，并满足纹理要求。新样本采齐并校验后，以四分之一新样本与四分之三旧模板融合。HOLD 期间冻结更新；LOST/VERIFY 使用初始模板重新确认，减少短期模板漂移。")
figure(doc, 4, "跟踪状态与双模板更新流程", "插入 TARGET 选取、TRACK、HOLD、LOST、VERIFY 及短期模板更新条件流程图", 3.5)
figure(doc, 5, "目标移动时的连续跟踪画面", "插入同一目标在不同位置的连续帧实拍图；标注红色或现用目标框、帧序号", 3.4)

head(doc, "6 验证结果与证据范围")
para(doc, "以下结果按实际证据来源分开列出。旧版的上板成功说明基础链路和当时的显示功能可运行；当前代码的功能仿真说明指定场景中逻辑符合预期；最终交付仍需要对最新源码重新综合、布局布线、检查时序并烧录实测。")
table(doc, ["对象与条件", "已记录结果", "证据性质"], [
    ("稳定基线位流", "用户反馈烧录后一切正常，可正常显示", "实物上板反馈；不代表最新改动"),
    ("10 月 31 日运动预测版本", "建立余量 +0.104 ns，保持余量 +0.020 ns；18981 slices、92 RAM、27 DSP", "当时版本实现报告"),
    ("双模板渐变场景", "固定模板 28/68 帧保持目标；双模板 68/68 帧保持目标", "合成视频仿真，不是自然场景统计"),
    ("当前显示与跟踪逻辑", "模式循环、红色轮廓、目标框显示规则、扩大搜索等定向测试通过", "RTL 功能仿真；完整回归曾中断"),
    ("最新双模板工程", "最终时序及重新上板效果待补", "尚无本次可引用的完整实现和实测记录"),
], [4.0, 8.4, 3.8])
para(doc, "合成渐变测试还检查了初始模板不被改写、遮挡时停止更新、重捕获以及更新期间取消目标的处理。28/68 与 68/68 是特定测试场景的帧数，不适合推断真实环境中的通用准确率。当前配置下的实物跟踪连续时间、误差和端到端帧率应在补图时同步记录。")
figure(doc, 6, "实物运行与仿真证据", "左侧插入当前实拍跟踪画面；右侧插入仿真波形或控制台结果，并分别注明版本与日期", 3.3)
figure(doc, 7, "最新工程实现报告", "待重新编译后插入时序余量、违例数与资源统计截图；截图需含工程版本信息", 3.1)

head(doc, "7 局限与后续工作")
para(doc, "当前跟踪以平移搜索和灰度模板为主，目标显著旋转、尺度变化、严重遮挡、突然高速运动或背景纹理相似时仍可能失锁。短期模板更新虽然通过初始模板约束，可降低渐变造成的匹配失效，却不能保证在所有场景中保持目标身份。显示红色轮廓采用轻量方向差分阈值，也会受噪声和光照变化影响。")
para(doc, "下一步按相同实物场景测量旧版与最新版：先重新生成位流并确认所有时钟域无时序违例，再记录静态、匀速、急转、短时遮挡和光照变化下的连续跟踪帧数、中心误差与重捕获时间。若仍出现一两秒后跟丢，应结合匹配分数、候选区分度、状态转换和输入帧更新信号定位原因，再调整阈值。")

head(doc, "8 演示方案与结论")
para(doc, "现场演示先展示摄像头实时画面，依次切换 RAW、GRAY、CANNY，指出 GRAY 红色轮廓；随后将目标移至画面中央，长按 KEY3 建立目标，移动物体观察目标框跟随，并演示短时遮挡及恢复。最后展示曝光档位和 RAW 锐化开关。演示中应明确当前烧录位流的生成日期与版本，避免将仿真画面误作现场结果。")
para(doc, "项目已形成完整的视频输入、处理、缓存和 HDMI 显示工程，并在此基础上实现多模式图像展示及动态跟踪。稳定基线的实物反馈确认了基础链路可用；最新算法改动在合成场景中改善了渐变外观下的连续匹配。最终竞赛成绩所需的时序、上板跟踪数据和实拍图片，应由最新工程重新验证后补入本报告。")

head(doc, "附录 A 关键工程文件与参数")
table(doc, ["项目", "位置或当前值"], [
    ("TD 工程", "reference_edge_project/td_project/camera_to_dsi_display.al"),
    ("显示流水线", "reference_edge_project/user_source/hdl_source/hx1p35_port/hx_vision_pipeline.v"),
    ("跟踪器", "reference_edge_project/user_source/hdl_source/hx1p35_port/hx_template_tracker.v"),
    ("局部搜索半径 / HOLD", "12 像素 / 10 帧"),
    ("模板 / 显示框", "64×64 区域中采样 8×8 点 / 80×80 像素"),
    ("灰度轮廓阈值", "32 灰度级"),
    ("相关验证入口", "tools/test_gray_contours_tracking.ps1"),
], [5.3, 10.9])
para(doc, "图片补充清单：图 1 系统框图；图 2 实物连接；图 3 三模式对比；图 4 跟踪流程；图 5 连续跟踪；图 6 实物与仿真证据；图 7 最新时序与资源。替换占位内容时，请在图注或正文注明拍摄或生成日期、位流版本及测试条件。")

OUT.parent.mkdir(parents=True, exist_ok=True)
doc.save(OUT)
print(OUT)
