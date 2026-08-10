#pragma once
#include "DocumentModel.h"
#include <QString>

// MOBI/AZW3 解析器：libmobi（third_party/libmobi）读 PDB → rawml 重建。
// 管线：mobi_init → mobi_load_filename（失败时按 mobi_is_encrypted 区分 DRM）→
// mobi_meta_get_title/author（EXTH）→ mobi_init_rawml + mobi_parse_rawml
// （自动识别 KF7/KF8，解压缩、重建 HTML 并把图片引用重写为
// src="resourceNNNNN.ext"）→ 拼接 rawml->markup 各 HTML 段 → 按 h1/h2 开新章、
// p/h3-h6/li/div 分段 → <img> 引用映射到 rawml->resources 解出的本地缓存文件
// （临时目录按书唯一，同 B4/B5 模式）→ 每段 SentenceSplitter 预分句。
// 出错置 lastError 并返回空模型（与 EpubParser/Fb2Parser 一致）。
class MobiParser {
public:
    DocumentModel parse(const QString &mobiPath);
    // 任务4：轻量元数据读取（只 init/load + EXTH，不重建 rawml）——
    // BookImporter 注册时以最小开销取 title/author/publisher
    DocumentModel readMetadataOnly(const QString &mobiPath);
    QString lastError() const { return m_error; }
private:
    QString m_error;
};
