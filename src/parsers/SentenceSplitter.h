#pragma once
#include <QString>
#include <QVector>

class SentenceSplitter {
public:
    static QVector<QString> split(const QString &text);
};
