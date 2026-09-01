import { useState } from "react";
import type { ReactNode } from "react";

export interface RetryRefreshProps {
  readonly announcementLabel: string;
  readonly buttonClassName: string;
  readonly children: ReactNode;
  readonly onRetry: () => void;
}

export function refreshAnnouncement(label: string, requestNumber: number): string {
  return `Refresh request ${requestNumber} sent for ${label}. Latest available data remains visible.`;
}

export function RetryRefresh({
  announcementLabel,
  buttonClassName,
  children,
  onRetry
}: RetryRefreshProps) {
  const [requestNumber, setRequestNumber] = useState(0);

  const retry = () => {
    setRequestNumber((current) => current + 1);
    onRetry();
  };

  return (
    <>
      <button className={buttonClassName} onClick={retry} type="button">{children}</button>
      <span aria-atomic="true" aria-live="polite" className="visually-hidden">
        {requestNumber > 0 ? refreshAnnouncement(announcementLabel, requestNumber) : ""}
      </span>
    </>
  );
}
