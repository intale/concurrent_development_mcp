import type { ReactNode } from "react";

export interface TableColumn<Row> {
  readonly key: string;
  readonly label: string;
  readonly render: (row: Row) => ReactNode;
  readonly className?: string;
}

export function DataTable<Row>({ caption, columns, rows, rowKey, emptyMessage = "No items to display." }: {
  readonly caption: string;
  readonly columns: readonly TableColumn<Row>[];
  readonly rows: readonly Row[];
  readonly rowKey: (row: Row) => string;
  readonly emptyMessage?: string;
}) {
  return (
    <div aria-label={`${caption} table`} className="table-responsive border rounded bg-body" role="region" tabIndex={0}>
      <table className="table table-striped table-hover align-middle mb-0">
        <caption className="visually-hidden">{caption}</caption>
        <thead className="table-light">
          <tr>{columns.map((column) => <th className={column.className} key={column.key} scope="col">{column.label}</th>)}</tr>
        </thead>
        <tbody>
          {rows.length === 0 ? <tr><td className="text-body-secondary py-4 text-center" colSpan={columns.length}>{emptyMessage}</td></tr> : rows.map((row) => (
            <tr key={rowKey(row)}>{columns.map((column, index) => index === 0
              ? <th className={`fw-normal text-break ${column.className ?? ""}`} key={column.key} scope="row">{column.render(row)}</th>
              : <td className={`text-break ${column.className ?? ""}`} key={column.key}>{column.render(row)}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function TextPreview({ text, limit = 140 }: { readonly text: string; readonly limit?: number }) {
  return <span title={text.length > limit ? text : undefined}>{text.length > limit ? `${text.slice(0, limit).trimEnd()}…` : text}</span>;
}

export function Timestamp({ value }: { readonly value: string | null }) {
  return value ? <time className="small text-nowrap" dateTime={value}>{new Date(value).toLocaleString()}</time> : <span className="text-body-secondary">—</span>;
}
