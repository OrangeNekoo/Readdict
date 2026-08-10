#pragma once
#include "DocumentModel.h"
#include <QString>

class ParserFactory {
public:
    // error（可选出参）：解析失败原因（具体解析器 lastError 透传）；成功为空串
    static DocumentModel parse(const QString &filePath, const QString &format, QString *error = nullptr);
    // 任务4：轻量元数据读取（title/author/publisher），供 BookImporter 注册时以
    // 最小开销取元数据、避免整书二次解析。EPUB 走 OPF 扫描、FB2 只扫 description、
    // MOBI/AZW3 只 init/load+EXTH；TXT/MD/PDF/未知格式无元数据来源返回空模型。
    // 任何失败同样返回空模型（调用方回退文件名，不阻断入库）。
    static DocumentModel readMetadata(const QString &filePath, const QString &format);
};
