#pragma once
#include <QString>
#include <QVector>
#include <QJsonObject>

struct Paragraph {
    QString text;          // 纯文本（用于 TTS/搜索）
    QString html;          // 轻量 HTML 子集（<b>/<i>/<h1..h6>）用于渲染
    int level = 0;         // 标题级别，0=正文
    QString imagePath;     // 图片引用（空表示无）
    QVector<QString> sentences; // 由 SentenceSplitter 预分句
};

struct Chapter {
    QString title;
    QVector<Paragraph> paragraphs;
    QJsonObject meta;      // 扩展元数据
};

struct DocumentModel {
    QString title, author;
    QVector<Chapter> chapters;
    bool empty() const { return chapters.isEmpty(); }
};
