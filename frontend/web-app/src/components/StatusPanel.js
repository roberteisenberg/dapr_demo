import React, { useState, useEffect, useRef } from 'react';
import { getLogs, clearLogs, subscribe, LogType } from '../services/statusLog';

const TAB_ACTIVITY = 'activity';
const TAB_SERVICES = 'services';

function formatTime(date) {
  return date.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function formatDuration(ms) {
  if (ms == null) return '';
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function logColor(type) {
  switch (type) {
    case LogType.REQUEST: return '#89b4fa';  // blue
    case LogType.RESPONSE: return '#a6e3a1'; // green
    case LogType.ERROR: return '#f38ba8';     // red
    case LogType.INFO: return '#cdd6f4';      // gray
    default: return '#cdd6f4';
  }
}

function statusBadge(status) {
  if (!status) return null;
  const color = status < 300 ? '#a6e3a1' : status < 500 ? '#fab387' : '#f38ba8';
  return <span style={{ color, fontWeight: 600, marginLeft: 6 }}>{status}</span>;
}

// Derive service health from recent logs
function deriveServices(logs) {
  const services = {};
  for (const log of logs) {
    if (!log.daprInfo) continue;
    const id = log.daprInfo.serviceId;
    if (!services[id]) {
      services[id] = { id, lastSeen: log.timestamp, requests: 0, errors: 0, buildingBlock: log.daprInfo.buildingBlock };
    }
    if (log.type === LogType.REQUEST) services[id].requests++;
    if (log.type === LogType.ERROR) services[id].errors++;
  }
  return Object.values(services);
}

// Group consecutive workflow polling entries
function groupLogs(logs) {
  const grouped = [];
  let pollGroup = null;

  for (const log of logs) {
    const isPolling = log.daprInfo?.serviceId === 'workflow-service' &&
      log.daprInfo?.method?.startsWith('/workflows/') &&
      log.httpMethod === 'GET' &&
      log.daprInfo?.method !== '/workflows';

    if (isPolling && log.type !== LogType.ERROR) {
      if (pollGroup) {
        pollGroup.count++;
        pollGroup.latest = log;
      } else {
        pollGroup = { type: 'poll-group', first: log, latest: log, count: 1 };
      }
    } else {
      if (pollGroup) {
        grouped.push(pollGroup);
        pollGroup = null;
      }
      grouped.push(log);
    }
  }
  if (pollGroup) grouped.push(pollGroup);
  return grouped;
}

export default function StatusPanel({ open, onClose }) {
  const [logs, setLogs] = useState(getLogs);
  const [tab, setTab] = useState(TAB_ACTIVITY);
  const listRef = useRef(null);

  useEffect(() => {
    const unsub = subscribe(setLogs);
    return unsub;
  }, []);

  if (!open) return null;

  const grouped = groupLogs(logs);
  const services = deriveServices(logs);

  return (
    <div className="status-panel">
      <div className="status-panel-header">
        <div className="status-panel-tabs">
          <button
            className={`status-tab ${tab === TAB_ACTIVITY ? 'active' : ''}`}
            onClick={() => setTab(TAB_ACTIVITY)}
          >
            Activity {logs.length > 0 && <span className="status-tab-count">{logs.length}</span>}
          </button>
          <button
            className={`status-tab ${tab === TAB_SERVICES ? 'active' : ''}`}
            onClick={() => setTab(TAB_SERVICES)}
          >
            Services
          </button>
        </div>
        <div className="status-panel-actions">
          <button className="status-clear-btn" onClick={clearLogs} title="Clear logs">Clear</button>
          <button className="status-close-btn" onClick={onClose} title="Close panel">&times;</button>
        </div>
      </div>

      {tab === TAB_ACTIVITY && (
        <div className="status-panel-body" ref={listRef}>
          {grouped.length === 0 && (
            <div className="status-empty">No activity yet. Try fetching products or creating an order.</div>
          )}
          {grouped.map((item, i) => {
            if (item.type === 'poll-group') {
              const log = item.latest;
              return (
                <div key={`poll-${i}`} className="status-log-entry" style={{ borderLeftColor: logColor(LogType.INFO) }}>
                  <span className="status-log-time">{formatTime(item.first.timestamp)}</span>
                  <span className="status-log-desc">
                    Poll workflow status <span className="status-poll-count">x{item.count}</span>
                  </span>
                  {log.duration != null && <span className="status-log-duration">{formatDuration(log.duration)}</span>}
                  {statusBadge(log.status)}
                </div>
              );
            }
            return (
              <div key={item.id} className="status-log-entry" style={{ borderLeftColor: logColor(item.type) }}>
                <span className="status-log-time">{formatTime(item.timestamp)}</span>
                <span className="status-log-type">{item.type}</span>
                <span className="status-log-desc">{item.description}</span>
                {item.duration != null && <span className="status-log-duration">{formatDuration(item.duration)}</span>}
                {statusBadge(item.status)}
                {item.error && <div className="status-log-error">{item.error}</div>}
              </div>
            );
          })}
        </div>
      )}

      {tab === TAB_SERVICES && (
        <div className="status-panel-body">
          {services.length === 0 && (
            <div className="status-empty">No services detected yet. Make some API calls first.</div>
          )}
          {services.map((svc) => (
            <div key={svc.id} className="status-service-card">
              <div className="status-service-name">{svc.id}</div>
              <div className="status-service-meta">
                <span>{svc.buildingBlock}</span>
                <span>{svc.requests} requests</span>
                {svc.errors > 0 && <span className="status-service-errors">{svc.errors} errors</span>}
              </div>
              <div className="status-service-seen">Last seen: {formatTime(svc.lastSeen)}</div>
            </div>
          ))}
          <div className="status-service-card status-service-note">
            <div className="status-service-name">notification-service</div>
            <div className="status-service-meta"><span>Event-driven (pub/sub subscriber, not directly observable)</span></div>
          </div>
        </div>
      )}
    </div>
  );
}
