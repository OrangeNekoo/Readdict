#pragma once
#include <QJsonObject>
#include <QObject>
#include <QString>

// QObject 基类 + Q_INVOKABLE：经 qmlRegisterSingletonInstance 注册为 QML 单例
// （Readdict.Backend.Settings），QML 侧用 value/setValue 读写点分键；
// QJsonValue 与 QML 的 string/number/bool 由 Qt 元类型系统自动互转。
class SettingsStore : public QObject {
    Q_OBJECT
public:
    explicit SettingsStore(const QString &path, QObject *parent = nullptr);
    Q_INVOKABLE QJsonValue value(const QString &dottedKey) const;
    Q_INVOKABLE void setValue(const QString &dottedKey, const QJsonValue &value);
    // D5：把用户选择的背景图片复制到 AppData/backgrounds/，返回复制后的绝对路径（失败返回空串）
    Q_INVOKABLE QString copyToBackgrounds(const QString &sourceUrl);
    void save();
    QString filePath() const { return m_path; }
    // 从磁盘重读并替换内存根对象（同步合并后调用），随后补默认分区
    void reloadFromDisk();
    QJsonObject root() const { return m_root; }
    // 整体替换根对象并原子落盘（同步合并写盘的唯一入口）
    void setRoot(const QJsonObject &root);
private:
    void applyDefaults();
    QString m_path;
    QJsonObject m_root;
};
