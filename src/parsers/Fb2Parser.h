#pragma once
#include "DocumentModel.h"
#include <QDir>
#include <QHash>
#include <QSet>
#include <QString>
#include <QXmlStreamReader>

// FB2 解析器：QXmlStreamReader 单文件两遍解析（FB2 是单个 XML 文件，无需解包）。
// 第一遍收集 <description> 元数据（book-title/author）与 <binary>（图片 base64）；
// 第二遍按 <body> 下 <section> 分章——<title> 内 <p> 文本为章标题（只进
// Chapter.title，不入段落列表），<p> 段落保留 <b>/<i>/<strong>/<em> 内联标签，
// 其余元素忽略标签、字符文本照收；<image l:href="#id"> 引用 <binary id="id">
// 的 base64 内容，解码后缓存到 QDir::temp() 下按书唯一的子目录
// （Readdict-<fb2 路径 md5>），Paragraph.imagePath 指向解出文件；每段经
// SentenceSplitter 预分句。
class Fb2Parser {
public:
    DocumentModel parse(const QString &fb2Path);
    // 任务4：轻量元数据读取（完整扫描整份 XML 校验良构，但不收集 binary/正文）——
    // BookImporter 注册时以最小开销取 title/author/publisher
    DocumentModel readMetadataOnly(const QString &fb2Path);
    QString lastError() const { return m_error; }
private:
    // 递归遍历 section（含嵌套小节）：标题/段落/子 section 填进同一章
    void parseSection(QXmlStreamReader &r, Chapter &ch);
    // 读取 <p> 内容拼成 Paragraph（html 保留内联标签，text 为纯文本）
    void parseParagraph(QXmlStreamReader &r, Paragraph &p);
    // 读取 <title> 内所有 <p> 的纯文本并拼接（消费到 </title>）
    QString readTitleText(QXmlStreamReader &r);
    // 读取 <description> 元数据（消费到 </description>）
    void readMetadata(QXmlStreamReader &r, DocumentModel *m);
    // 读取 <author> 的 first-name/middle-name/last-name（消费到 </author>）
    QString readAuthor(QXmlStreamReader &r);
    // 消费未知元素直到其匹配结束标签（含嵌套元素）
    static void skipElement(QXmlStreamReader &r);

    QHash<QString, QByteArray> m_binaries; // binary id → base64 原文
    QHash<QString, QString> m_binaryTypes; // binary id → content-type（补扩展名用）
    QDir m_imgDir;                         // 图片缓存目录（按书唯一）
    QSet<QString> m_imgNames;              // 已用图片文件名（去重）
    QString m_error;                         // 最近一次解析失败原因（成功清空）
};
