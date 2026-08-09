import QtQuick
pragma Singleton

// L9（P2#33）：背景模式归一化公共单例——ReaderPage 与 SettingsBackgroundPage 的
// background/mode 四态白名单校验抽到这里，避免两处重复白名单分叉。
// 非法/缺失值（含旧版 eink）统一归一为 "light"。
//
// 机制：同 Theme.qml——QML 文件单例，经 qmlRegisterSingletonType(QUrl) 注册为
// Readdict.UI/BackgroundNorm（main.cpp 与 tst_qmlmain.cpp 各注册一次）。
QtObject {
    function norm(mode) {
        return ["light", "dark", "paper", "image"].includes(mode) ? mode : "light"
    }
}
