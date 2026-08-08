#pragma once
#include "DocumentModel.h"
#include <QString>

class TextParser {
public:
    DocumentModel parse(const QString &filePath);
    QString lastError() const { return m_error; }
private:
    // 打开/编码探测失败时经 error 上抛原因（空文件不算错误——零章 TXT 语义）
    static QString detectAndRead(const QString &filePath, QString *error);
    static QString mdToHtml(const QString &line);
    QString m_error;
};
