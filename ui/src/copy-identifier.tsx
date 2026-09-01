import { useState } from "react";

export interface CopyIdentifierProps {
  readonly label: string;
  readonly value: string;
}

export function copyResultAnnouncement(label: string, copied: boolean): string {
  return copied ? `${label} copied.` : `${label} could not be copied.`;
}

export function CopyIdentifier({ label, value }: CopyIdentifierProps) {
  const [announcement, setAnnouncement] = useState("");

  const copy = async () => {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard API unavailable");
      await navigator.clipboard.writeText(value);
      setAnnouncement(copyResultAnnouncement(label, true));
    } catch {
      setAnnouncement(copyResultAnnouncement(label, false));
    }
  };

  return (
    <span className="d-flex flex-column flex-sm-row align-items-sm-center gap-2">
      <code className="text-break flex-grow-1">{value}</code>
      <button
        aria-label={`Copy ${label}`}
        className="btn btn-outline-secondary"
        onClick={() => { void copy(); }}
        type="button"
      >
        <i aria-hidden="true" className="bi bi-copy me-1" /> Copy
      </button>
      <span aria-atomic="true" aria-live="polite" className="visually-hidden">
        {announcement}
      </span>
    </span>
  );
}
