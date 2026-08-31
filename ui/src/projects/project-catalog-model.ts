export interface ProjectRow {
  readonly id: string;
  readonly name: string;
  readonly paths: string;
  readonly registeredAt: string;
  readonly remotes: string;
  readonly scope: string;
}

export function preservePageForExactScope<TData>(
  previousData: TData | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  exactScope: string
): TData | undefined {
  return previousQueryKey?.[1] === exactScope ? previousData : undefined;
}
