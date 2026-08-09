import QtQuick
import Readdict.UI 1.0

// U4：Kindle 线性描边图标集（分析报告 §2/§4/§5：stroke-only、24-28px、无填充）。
// Canvas 绘制（矢量路径），不依赖系统字体字形（U2 占位字符 ⌂▤⇄⚙ 的平台 tofu 疑虑
// 由此消除——底部标签与阅读页 Sheet/菜单统一走本组件）。
// 可用图标名（24x24 网格，线宽 1.8 round cap）：
//   shelf 书库(首页) / stats 统计 / sync 同步 / settings 设置 / toc 目录 /
//   theme 主题 / font 字体 / layout 布局 / more 更多 / back 返回 /
//   search 搜索 / prev 上一章 / next 下一章 / read 朗读 / notes 笔记 /
//   chevron 右箭头 / globe 语言 / image 图片背景 /
//   import 导入 / info 信息 / bookmark 书签 / bookmarkFill 书签(实心) /
//   dot 圆点（菜单兜底） / filter 筛选
// 接口：name（图标名）、color（描边色，默认 textPrimary）、size（边长，默认 24）。
Item {
    id: kdIcon

    property string name: ""
    property color color: UITheme.textPrimary
    property int size: 24

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: kdIcon.drawIcon(getContext("2d"))

        // 属性变化重绘（绑定式连接——requestPaint 不依赖依赖追踪）
        Connections {
            target: kdIcon
            function onNameChanged() { canvas.requestPaint() }
            function onColorChanged() { canvas.requestPaint() }
            function onSizeChanged() { canvas.requestPaint() }
        }
    }

    // ---- 绘图辅助（24x24 逻辑网格，按 size/24 缩放）----
    function seg(ctx, x1, y1, x2, y2) {
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
    }
    function poly(ctx, pts, closePath) {
        ctx.beginPath()
        ctx.moveTo(pts[0][0], pts[0][1])
        for (let i = 1; i < pts.length; ++i) ctx.lineTo(pts[i][0], pts[i][1])
        if (closePath) ctx.closePath()
        ctx.stroke()
    }
    function ring(ctx, cx, cy, r) {
        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
    }

    // ---- 图标绘制（CanvasRenderingContext2D）----
    function drawIcon(ctx) {
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        if (!kdIcon.name) return
        ctx.save()
        const s = kdIcon.size / 24
        ctx.scale(s, s)
        ctx.lineWidth = 1.8
        ctx.strokeStyle = kdIcon.color
        ctx.fillStyle = kdIcon.color
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        switch (kdIcon.name) {
        // 书库/首页：房子轮廓 + 门
        case "shelf":
            poly(ctx, [[4.5,11.5],[12,4.5],[19.5,11.5]], false)
            poly(ctx, [[4.5,11.5],[4.5,19.5],[19.5,19.5],[19.5,11.5]], true)
            poly(ctx, [[10,19.5],[10,14.5],[14,14.5],[14,19.5]], true)
            break
        // 统计：三根柱条 + 基线
        case "stats":
            seg(ctx, 6.5, 20, 6.5, 10)
            seg(ctx, 12, 20, 12, 6)
            seg(ctx, 17.5, 20, 17.5, 13)
            seg(ctx, 4, 20.5, 20, 20.5)
            break
        // 同步：环形箭头（右上缺口，端点箭头指示旋转方向）
        case "sync": {
            const r = 7.5
            const a0 = 0.30 * Math.PI
            const a1 = a0 + 1.6 * Math.PI
            ctx.beginPath(); ctx.arc(12, 12, r, a0, a1); ctx.stroke()
            const ex = 12 + r * Math.cos(a1), ey = 12 + r * Math.sin(a1)
            const ang = a1 + Math.PI / 2          // 顺时针切线方向
            ctx.beginPath()
            ctx.moveTo(ex, ey)
            ctx.lineTo(ex + 3.4 * Math.cos(ang + 0.65), ey + 3.4 * Math.sin(ang + 0.65))
            ctx.moveTo(ex, ey)
            ctx.lineTo(ex + 3.4 * Math.cos(ang - 0.65), ey + 3.4 * Math.sin(ang - 0.65))
            ctx.stroke()
            break
        }
        // 设置：齿轮（中心圆 + 6 辐条）
        case "settings":
            ring(ctx, 12, 12, 5)
            for (let i = 0; i < 6; ++i) {
                const a = i * Math.PI / 3
                seg(ctx, 12 + 8 * Math.cos(a), 12 + 8 * Math.sin(a),
                    12 + 10.5 * Math.cos(a), 12 + 10.5 * Math.sin(a))
            }
            break
        // 目录：三横线
        case "toc":
            seg(ctx, 5, 6.5, 19, 6.5)
            seg(ctx, 5, 12, 19, 12)
            seg(ctx, 5, 17.5, 19, 17.5)
            break
        // 主题：太阳（圆 + 8 光芒）
        case "theme":
            ring(ctx, 12, 12, 6.5)
            for (let i = 0; i < 8; ++i) {
                const a = i * Math.PI / 4
                seg(ctx, 12 + 9 * Math.cos(a), 12 + 9 * Math.sin(a),
                    12 + 11.5 * Math.cos(a), 12 + 11.5 * Math.sin(a))
            }
            break
        // 字体：字母 A（两斜边 + 横杠）
        case "font":
            poly(ctx, [[9.5,18.5],[12,6.5],[14.5,18.5]], false)
            seg(ctx, 10.4, 14.5, 13.6, 14.5)
            break
        // 布局：2×2 网格
        case "layout":
            poly(ctx, [[4.5,4.5],[11.25,4.5],[11.25,11.25],[4.5,11.25]], true)
            poly(ctx, [[12.75,4.5],[19.5,4.5],[19.5,11.25],[12.75,11.25]], true)
            poly(ctx, [[4.5,12.75],[11.25,12.75],[11.25,19.5],[4.5,19.5]], true)
            poly(ctx, [[12.75,12.75],[19.5,12.75],[19.5,19.5],[12.75,19.5]], true)
            break
        // 更多：三点
        case "more":
            ring(ctx, 6, 12, 1.7)
            ring(ctx, 12, 12, 1.7)
            ring(ctx, 18, 12, 1.7)
            break
        // 返回：左向箭头（折叠）
        case "back":
            poly(ctx, [[14.5,5.5],[8,12],[14.5,18.5]], false)
            break
        // 搜索：放大镜
        case "search":
            ring(ctx, 10.5, 10.5, 6)
            seg(ctx, 14.8, 14.8, 19.5, 19.5)
            break
        // 上一章：左竖线 + 左向折叠
        case "prev":
            seg(ctx, 6, 5, 6, 19)
            poly(ctx, [[11.5,5],[5.5,12],[11.5,19]], false)
            break
        // 下一章：右竖线 + 右向折叠（镜像）
        case "next":
            seg(ctx, 18, 5, 18, 19)
            poly(ctx, [[12.5,5],[18.5,12],[12.5,19]], false)
            break
        // 朗读：扬声器 + 声波弧线
        case "read":
            poly(ctx, [[6.5,9.5],[9.5,9.5],[14,5.5],[14,18.5],[9.5,14.5],[6.5,14.5]], true)
            ctx.beginPath(); ctx.arc(16.5, 12, 2.4, -0.55 * Math.PI, 0.55 * Math.PI); ctx.stroke()
            ctx.beginPath(); ctx.arc(19.2, 12, 4.6, -0.6 * Math.PI, 0.6 * Math.PI); ctx.stroke()
            break
        // 笔记：文档 + 文字行
        case "notes":
            poly(ctx, [[6.5,4.5],[17.5,4.5],[17.5,19.5],[6.5,19.5]], true)
            seg(ctx, 9.5, 9, 15, 9)
            seg(ctx, 9.5, 12.5, 15, 12.5)
            seg(ctx, 9.5, 16, 13, 16)
            break
        // 右箭头 chevron（U5：列表项进入子页指示，同分析报告 §4 "›"）
        case "chevron":
            poly(ctx, [[9.5,6],[15.5,12],[9.5,18]], false)
            break
        // 语言/地球（U5：设置页语言行图标）
        case "globe":
            ring(ctx, 12, 12, 8)
            seg(ctx, 4, 12, 20, 12)
            ctx.beginPath(); ctx.ellipse(12, 12, 3.6, 8, 0, 0, Math.PI * 2); ctx.stroke()
            break
        // 图片/背景（U5：设置页阅读背景行图标——画框 + 山丘 + 太阳）
        case "image":
            poly(ctx, [[4.5,4.5],[19.5,4.5],[19.5,19.5],[4.5,19.5]], true)
            poly(ctx, [[5.5,17.5],[10,11.5],[13.5,15.5],[16,12.5],[18.5,17.5]], false)
            ring(ctx, 15.5, 8, 1.6)
            break
        // 导入：下箭头落入托盘（U1：菜单项"导入"）
        case "import":
            seg(ctx, 12, 4.5, 12, 13.5)
            poly(ctx, [[8.5,10.2],[12,13.7],[15.5,10.2]], false)
            poly(ctx, [[4.5,14.5],[4.5,19.5],[19.5,19.5],[19.5,14.5]], false)
            break
        // 信息：圆 + i（U1：菜单项"关于/信息"）
        case "info":
            ring(ctx, 12, 12, 8)
            seg(ctx, 12, 11, 12, 16.5)
            ctx.beginPath(); ctx.arc(12, 7.8, 1.1, 0, Math.PI * 2); ctx.fill()
            break
        // 书签：缎带（U1：菜单项"书签"；bookmarkFill 为其实心变体）
        case "bookmark":
            poly(ctx, [[7,4.5],[17,4.5],[17,19.5],[12,15.5],[7,19.5]], true)
            break
        case "bookmarkFill":
            ctx.beginPath()
            ctx.moveTo(7, 4.5); ctx.lineTo(17, 4.5); ctx.lineTo(17, 19.5)
            ctx.lineTo(12, 15.5); ctx.lineTo(7, 19.5); ctx.closePath(); ctx.fill()
            break
        // 圆点：菜单无图标条目的兜底占位（填充小圆）
        case "dot":
            ctx.beginPath(); ctx.arc(12, 12, 2.2, 0, Math.PI * 2); ctx.fill()
            break
        // 筛选：漏斗（U1：筛选入口）
        case "filter":
            poly(ctx, [[4.5,5.5],[19.5,5.5],[14,12],[14,19],[10,19],[10,12]], true)
            break
        default:
            break   // 未知图标名：不绘制（静默，保持布局占位）
        }
        ctx.restore()
    }
}
