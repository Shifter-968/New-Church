import React from 'react'

export default function ActionLabel({ busy, pending, children }) {
  return <span className="action-label" role="status" aria-live="polite">
    {busy && <span className="action-spinner" aria-hidden="true" />}
    {busy ? pending : children}
  </span>
}
