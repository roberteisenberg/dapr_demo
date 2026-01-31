import React, { useState, useEffect } from 'react';
import { subscribe, getLogs } from '../services/statusLog';

export default function StatusToggleButton({ open, onClick }) {
  const [count, setCount] = useState(0);
  const [lastSeen, setLastSeen] = useState(0);

  useEffect(() => {
    const unsub = subscribe((logs) => {
      if (!open && logs.length > 0) {
        setCount(logs.length - lastSeen);
      }
    });
    return unsub;
  }, [open, lastSeen]);

  useEffect(() => {
    if (open) {
      setLastSeen(getLogs().length);
      setCount(0);
    }
  }, [open]);

  return (
    <button
      className={`status-fab ${open ? 'status-fab-active' : ''}`}
      onClick={onClick}
      title={open ? 'Close status panel' : 'Open status panel'}
    >
      {open ? '\u2715' : '\u25C9'}
      {!open && count > 0 && <span className="status-fab-badge">{count > 99 ? '99+' : count}</span>}
    </button>
  );
}
