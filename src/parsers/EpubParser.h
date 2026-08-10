#pragma once
#include "DocumentModel.h"
#include <QDir>
#include <QHash>
#include <QSet>
#include <QString>

// EPUB 解析器：minizip 解包 + container.xml/OPF 解析 + XHTML 归一化。
// 管线：META-INF/container.xml → rootfile（content.opf）→ 元数据（dc:title/dc:creator）、
// manifest（id→href）、spine（idref 顺序）→ 按 spine 顺序逐章读 XHTML →
// normalizeXhtml 归一化（保留 p/h1-h3/b/i/em/strong/li/ul/ol/img，丢弃其余）→
// splitParagraphs 按 <p>/<h1..3>/<li> 切分段落。图片 <img src> 从 zip 解出
// 二进制，缓存到 QDir::temp() 下按书唯一的子目录，Paragraph.imagePath 指向
// 解出的文件；每段经 SentenceSplitter 预分句。
class EpubParser {
public:
    DocumentModel parse(const QString &epubPath);
    // 任务4：轻量元数据读取（仅 container/OPF 扫描，不解析章节）——BookImporter
    // 注册时以最小开销取 title/author/publisher；缺失/损坏/缺 spine/XML 错误
    // 返回空模型不设错误（与 parse() 的有效性语义一致）
    DocumentModel readMetadata(const QString &epubPath);
    QString lastError() const { return m_error; }
private:
    QByteArray readZipEntry(const QString &zipPath, const QString &entry,
                            QString *error = nullptr) const;
    QString normalizeXhtml(const QByteArray &xhtml, QString *title) const;
    // 从 zip 解出图片条目并缓存到 dir，按条目路径去重；命名与磁盘状态无关
    // （同名冲突加条目 md5 前缀），已存在的目标文件直接复用；返回本地文件路径
    QString extractImage(const QString &zipPath, const QString &entry,
                         const QDir &dir, QHash<QString, QString> *cache,
                         QSet<QString> *seenNames) const;
    // 归一化 html → 段落（<img> 顺带解出到 imgDir）
    void splitParagraphs(const QString &html, const QString &zipPath,
                         const QString &chapterEntry, const QDir &imgDir,
                         QHash<QString, QString> *imgCache,
                         QSet<QString> *imgNames,
                         QVector<Paragraph> *out) const;
    QString m_error;
};
