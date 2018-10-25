#include "logsmodelng.h"
#include <QDateTime>
#include <QDebug>
#include <QMetaEnum>

#include "engine.h"
#include "types/logentry.h"
#include "logmanager.h"

LogsModelNg::LogsModelNg(QObject *parent) : QAbstractListModel(parent)
{

}

Engine *LogsModelNg::engine() const
{
    return m_engine;
}

void LogsModelNg::setEngine(Engine *engine)
{
    if (m_engine != engine) {
        m_engine = engine;
        connect(engine->logManager(), &LogManager::logEntryReceived, this, &LogsModelNg::newLogEntryReceived);
        emit engineChanged();
    }
}

int LogsModelNg::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_list.count();
}

QVariant LogsModelNg::data(const QModelIndex &index, int role) const
{
    switch (role) {
    case RoleTimestamp:
        return m_list.at(index.row())->timestamp();
    case RoleValue:
        return m_list.at(index.row())->value();
    case RoleDeviceId:
        return m_list.at(index.row())->deviceId();
    case RoleTypeId:
        return m_list.at(index.row())->typeId();
    case RoleSource:
        return m_list.at(index.row())->source();
    case RoleLoggingEventType:
        return m_list.at(index.row())->loggingEventType();
    }
    return QVariant();
}

QHash<int, QByteArray> LogsModelNg::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles.insert(RoleTimestamp, "timestamp");
    roles.insert(RoleValue, "value");
    roles.insert(RoleDeviceId, "deviceId");
    roles.insert(RoleTypeId, "typeId");
    roles.insert(RoleSource, "source");
    roles.insert(RoleLoggingEventType, "loggingEventType");
    return roles;
}

bool LogsModelNg::busy() const
{
    return m_busy;
}

bool LogsModelNg::live() const
{
    return m_live;
}

void LogsModelNg::setLive(bool live)
{
    if (m_live != live) {
        m_live = live;
        emit liveChanged();
    }
}

QString LogsModelNg::deviceId() const
{
    return m_deviceId;
}

void LogsModelNg::setDeviceId(const QString &deviceId)
{
    if (m_deviceId != deviceId) {
        m_deviceId = deviceId;
        emit deviceIdChanged();
    }
}

QStringList LogsModelNg::typeIds() const
{
    return m_typeIds;
}

void LogsModelNg::setTypeIds(const QStringList &typeIds)
{
    if (m_typeIds != typeIds) {
        m_typeIds = typeIds;
        emit typeIdsChanged();
    }
}

QDateTime LogsModelNg::startTime() const
{
    return m_startTime;
}

void LogsModelNg::setStartTime(const QDateTime &startTime)
{
    if (m_startTime != startTime) {
        m_startTime = startTime;
        emit startTimeChanged();
    }
}

QDateTime LogsModelNg::endTime() const
{
    return m_endTime;
}

void LogsModelNg::setEndTime(const QDateTime &endTime)
{
    if (m_endTime != endTime) {
        m_endTime = endTime;
        emit endTimeChanged();
    }
}

QtCharts::QXYSeries *LogsModelNg::graphSeries() const
{
    return m_graphSeries;
}

void LogsModelNg::setGraphSeries(QtCharts::QXYSeries *graphSeries)
{
    m_graphSeries = graphSeries;
}

QDateTime LogsModelNg::viewStartTime() const
{
    return m_viewStartTime;
}

void LogsModelNg::setViewStartTime(const QDateTime &viewStartTime)
{
    if (m_viewStartTime != viewStartTime) {
        m_viewStartTime = viewStartTime;
        emit viewStartTimeChanged();
        if (m_list.count() == 0 || m_list.last()->timestamp() > m_viewStartTime) {
            if (canFetchMore()) {
                fetchMore();
            }
        }
    }
}

QVariant LogsModelNg::minValue() const
{
    qDebug() << "returning min value" << m_minValue;
    return m_minValue;
}

QVariant LogsModelNg::maxValue() const
{
    qDebug() << "returning max value" << m_maxValue;
    return m_maxValue;
}

void LogsModelNg::logsReply(const QVariantMap &data)
{
//    qDebug() << "logs reply" << data;

    m_busy = false;
    emit busyChanged();

    int offset = data.value("params").toMap().value("offset").toInt();
    int count = data.value("params").toMap().value("count").toInt();

    QList<LogEntry*> newBlock;
    QList<QVariant> logEntries = data.value("params").toMap().value("logEntries").toList();
    foreach (const QVariant &logEntryVariant, logEntries) {
        QVariantMap entryMap = logEntryVariant.toMap();
        QDateTime timeStamp = QDateTime::fromMSecsSinceEpoch(entryMap.value("timestamp").toLongLong());
        QString deviceId = entryMap.value("deviceId").toString();
        QString typeId = entryMap.value("typeId").toString();
        QMetaEnum sourceEnum = QMetaEnum::fromType<LogEntry::LoggingSource>();
        LogEntry::LoggingSource loggingSource = static_cast<LogEntry::LoggingSource>(sourceEnum.keyToValue(entryMap.value("source").toByteArray()));
        QMetaEnum loggingEventTypeEnum = QMetaEnum::fromType<LogEntry::LoggingEventType>();
        LogEntry::LoggingEventType loggingEventType = static_cast<LogEntry::LoggingEventType>(loggingEventTypeEnum.keyToValue(entryMap.value("eventType").toByteArray()));
        QVariant value = loggingEventType == LogEntry::LoggingEventTypeActiveChange ? entryMap.value("active").toBool() : entryMap.value("value");
        LogEntry *entry = new LogEntry(timeStamp, value, deviceId, typeId, loggingSource, loggingEventType, this);
        newBlock.append(entry);
    }

    if (count < m_blockSize) {
        m_canFetchMore = false;
    }

    if (newBlock.isEmpty()) {
        return;
    }

    beginInsertRows(QModelIndex(), offset, offset + newBlock.count() - 1);
    QVariant newMin = m_minValue;
    QVariant newMax = m_maxValue;
    for (int i = 0; i < newBlock.count(); i++) {
        LogEntry *entry = newBlock.at(i);
        m_list.insert(offset + i, entry);
        qDebug() << "Adding line series point:" << i << entry->timestamp().toSecsSinceEpoch() << entry->value().toReal();
        if (m_graphSeries) {
            m_graphSeries->insert(offset + i, QPointF(entry->timestamp().toMSecsSinceEpoch(), entry->value().toReal()));
        }
        if (!newMin.isValid() || newMin > entry->value()) {
            newMin = entry->value().toReal();
        }
        if (!newMax.isValid() || newMax < entry->value()) {
            newMax = entry->value().toReal();
        }
    }
    endInsertRows();
    emit countChanged();
    qDebug() << "min" << m_minValue << "max" << m_maxValue << "newMin" << newMin << "newMax" << newMax;
    if (m_minValue != newMin) {
        m_minValue = newMin;
        emit minValueChanged();
    }
    if (m_maxValue != newMax) {
        m_maxValue = newMax;
        emit maxValueChanged();
    }

    if (m_list.count() > 0 && m_list.last()->timestamp() > m_viewStartTime && canFetchMore()) {
        fetchMore();
    }
}

void LogsModelNg::fetchMore(const QModelIndex &parent)
{
    Q_UNUSED(parent)
    qDebug() << "fetchMore called";

    if (!m_engine->jsonRpcClient()) {
        qWarning() << "Cannot update. JsonRpcClient not set";
        return;
    }
    if (m_busy) {
        return;
    }

    if ((!m_startTime.isNull() && m_endTime.isNull()) || (m_startTime.isNull() && !m_endTime.isNull())) {
        // Need neither or both, startTime and endTime set
        return;
    }

    m_busy = true;
    emit busyChanged();

    QVariantMap params;
    if (!m_deviceId.isEmpty()) {
        QVariantList deviceIds;
        deviceIds.append(m_deviceId);
        params.insert("deviceIds", deviceIds);
    }
    if (!m_typeIds.isEmpty()) {
        QVariantList typeIds;
        foreach (const QString &typeId, m_typeIds) {
            typeIds.append(typeId);
        }
        params.insert("typeIds", typeIds);
    }
    if (!m_startTime.isNull() && !m_endTime.isNull()) {
        QVariantList timeFilters;
        QVariantMap timeFilter;
        timeFilter.insert("startDate", m_startTime.toSecsSinceEpoch());
        timeFilter.insert("endDate", m_endTime.toSecsSinceEpoch());
        timeFilters.append(timeFilter);
        params.insert("timeFilters", timeFilters);
    }

    params.insert("limit", m_blockSize);
    params.insert("offset", m_list.count());

    m_engine->jsonRpcClient()->sendCommand("Logging.GetLogEntries", params, this, "logsReply");
    qDebug() << "GetLogEntries called";
}

bool LogsModelNg::canFetchMore(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    qDebug() << "canFetchMore" << m_canFetchMore;
    return m_canFetchMore;
}

void LogsModelNg::newLogEntryReceived(const QVariantMap &data)
{
    if (!m_live) {
        return;
    }

    QVariantMap entryMap = data;
    QString deviceId = entryMap.value("deviceId").toString();
    if (!m_deviceId.isNull() && deviceId != m_deviceId) {
        return;
    }

    QString typeId = entryMap.value("typeId").toString();
    if (!m_typeIds.isEmpty() && !m_typeIds.contains(typeId)) {
        return;
    }

    beginInsertRows(QModelIndex(), 0, 0);
    QDateTime timeStamp = QDateTime::fromMSecsSinceEpoch(entryMap.value("timestamp").toLongLong());
    QMetaEnum sourceEnum = QMetaEnum::fromType<LogEntry::LoggingSource>();
    LogEntry::LoggingSource loggingSource = static_cast<LogEntry::LoggingSource>(sourceEnum.keyToValue(entryMap.value("source").toByteArray()));
    QMetaEnum loggingEventTypeEnum = QMetaEnum::fromType<LogEntry::LoggingEventType>();
    LogEntry::LoggingEventType loggingEventType = static_cast<LogEntry::LoggingEventType>(loggingEventTypeEnum.keyToValue(entryMap.value("eventType").toByteArray()));
    QVariant value = loggingEventType == LogEntry::LoggingEventTypeActiveChange ? entryMap.value("active").toBool() : entryMap.value("value");
    LogEntry *entry = new LogEntry(timeStamp, value, deviceId, typeId, loggingSource, loggingEventType, this);
    m_list.prepend(entry);
    if (m_graphSeries) {
        m_graphSeries->insert(0, QPointF(entry->timestamp().toMSecsSinceEpoch(), entry->value().toReal()));
    }
    endInsertRows();
    emit countChanged();

}


