import QtQuick

// 阅读背景层：浅色 #FAFAFA / 深色 #121212 / 米白 #F5EFE0
// 图片背景与模糊/亮度在计划 D 实现
Rectangle {
    id: bg
    property string mode: "light"   // light | dark | paper
    color: mode === "dark" ? "#121212" : (mode === "paper" ? "#F5EFE0" : "#FAFAFA")
}
