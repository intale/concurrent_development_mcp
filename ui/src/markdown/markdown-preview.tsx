import { createContext, useCallback, useContext, useState } from "react";
import { createPortal } from "react-dom";
import { MarkdownDocument } from "./markdown-document.js";
import type { MarkdownDocumentProps } from "./markdown-document.js";

// The entry point provides the trusted stylesheet as text, never a global CSS import.
export const MarkdownStylesContext = createContext("");

export function MarkdownPreview(properties: MarkdownDocumentProps) {
  const styles = useContext(MarkdownStylesContext);
  const [root, setRoot] = useState<ShadowRoot | null>(null);
  const attachPreview = useCallback((host: HTMLDivElement | null) => {
    if (host) setRoot(host.shadowRoot ?? host.attachShadow({ mode: "open" }));
  }, []);

  return (
    <div aria-label="Markdown preview" className="border rounded bg-body p-3 overflow-auto" role="region" tabIndex={0}>
      <div data-markdown-preview="" ref={attachPreview} style={{ all: "initial", display: "block" }}>
        {root ? createPortal(<><style>{styles}</style><MarkdownDocument {...properties} /></>, root) : null}
      </div>
    </div>
  );
}
