import type { LatestUpdateSort } from "./gql/graphql.js";

export const DEFAULT_LATEST_UPDATE_SORT: LatestUpdateSort = "NEWEST_FIRST";

export function parseLatestUpdateSort(value: string | null): LatestUpdateSort {
  return value === "OLDEST_FIRST" ? "OLDEST_FIRST" : DEFAULT_LATEST_UPDATE_SORT;
}

export function latestUpdateSortParams(
  current: URLSearchParams,
  sort: LatestUpdateSort
): URLSearchParams {
  const next = new URLSearchParams(current);
  next.delete("after");
  next.delete("trail");
  if (sort === DEFAULT_LATEST_UPDATE_SORT) next.delete("sort");
  else next.set("sort", sort);
  return next;
}

export function LatestUpdateSortControl({ id, onChange, value }: {
  readonly id: string;
  readonly onChange: (value: LatestUpdateSort) => void;
  readonly value: LatestUpdateSort;
}) {
  return (
    <div className="col-12 col-sm-6 col-lg-3">
      <label className="form-label" htmlFor={id}>Latest update</label>
      <select
        className="form-select"
        id={id}
        onChange={(event) => onChange(event.target.value as LatestUpdateSort)}
        value={value}
      >
        <option value="NEWEST_FIRST">Newest first</option>
        <option value="OLDEST_FIRST">Oldest first</option>
      </select>
    </div>
  );
}
