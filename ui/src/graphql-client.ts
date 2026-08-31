import { print } from "graphql";
import type { TypedDocumentNode } from "@graphql-typed-document-node/core";

interface GraphqlErrorPayload {
  readonly message: string;
  readonly extensions?: Readonly<Record<string, unknown>>;
}

interface GraphqlResponse<TData> {
  readonly data?: TData;
  readonly errors?: readonly GraphqlErrorPayload[];
}

export class GraphqlRequestError extends Error {
  readonly errors: readonly GraphqlErrorPayload[];

  constructor(message: string, errors: readonly GraphqlErrorPayload[] = []) {
    super(message);
    this.name = "GraphqlRequestError";
    this.errors = errors;
  }
}

export async function executeGraphql<TData, TVariables>(
  document: TypedDocumentNode<TData, TVariables>,
  variables: TVariables,
  signal?: AbortSignal
): Promise<TData> {
  const response = await fetch("/graphql", {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json"
    },
    body: JSON.stringify({ query: print(document), variables }),
    ...(signal ? { signal } : {})
  });

  if (!response.ok) {
    throw new GraphqlRequestError(`GraphQL request failed with HTTP ${response.status}`);
  }

  const payload: unknown = await response.json();
  const envelope = payload as GraphqlResponse<TData>;
  if (envelope.errors?.length) {
    throw new GraphqlRequestError(envelope.errors.map((error) => error.message).join("; "), envelope.errors);
  }
  if (envelope.data === undefined) {
    throw new GraphqlRequestError("GraphQL response did not contain data");
  }

  return envelope.data;
}
