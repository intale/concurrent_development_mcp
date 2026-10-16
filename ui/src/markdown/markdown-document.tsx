import ReactMarkdown from "react-markdown";
import remarkFrontmatter from "remark-frontmatter";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import { unified } from "unified";
import { ContextLink } from "../navigation.js";

export interface MarkdownDocumentProps {
  readonly text: string;
  readonly assetLinks?: ReadonlyMap<string, string> | undefined;
}

const ordinaryMarkdown = unified().use(remarkParse).use(remarkGfm);
type MarkdownRoot = ReturnType<typeof ordinaryMarkdown.parse>;

function documentMetadata() {
  return (tree: MarkdownRoot, file: { toString(): string }) => {
    if (!tree.children.some((node) => node.type === "yaml")) return;
    const source = file.toString();
    let cursor = 0;
    let renderedSource = "";
    const metadataStarts = new Set<number>();
    tree.children.forEach((node, index) => {
      if (node.type !== "yaml") return;
      // A preserved document may have one introductory paragraph before its metadata.
      // Do not turn ordinary sections separated by horizontal rules into metadata.
      const mapping = /^(?:[ \t]*(?:#[^\r\n]*)?\r?\n)*[ \t]*(?:[\w.-]+|"[^"\r\n]+"|'[^'\r\n]+'):(?:[ \t]|\r?\n|$)/.test(node.value);
      const metadataPosition = index === 0 || (index === 1 && tree.children[0]?.type === "paragraph");
      if (!mapping || !metadataPosition) return;

      // Positions are supplied by the Markdown parser. Fence generation protects
      // literal backticks in metadata without interpreting any YAML values.
      renderedSource += source.slice(cursor, node.position!.start.offset!);
      metadataStarts.add(renderedSource.length);
      let fenceLength = 3;
      for (const match of node.value.matchAll(/`+/g)) fenceLength = Math.max(fenceLength, match[0].length + 1);
      const fence = "`".repeat(fenceLength);
      renderedSource += `${fence}yaml\n${node.value}\n${fence}`;
      cursor = node.position!.end.offset!;
    });

    // Parse the complete document, not isolated fragments: reference definitions
    // and GFM footnotes must remain visible to uses elsewhere in the same document.
    const parsed = ordinaryMarkdown.parse(renderedSource + source.slice(cursor));
    parsed.children.forEach((node) => {
      if (node.type === "code" && metadataStarts.has(node.position!.start.offset!)) {
        node.data = { ...node.data, hProperties: { "data-document-metadata": "" } };
      }
    });
    tree.children = parsed.children;
  };
}

export function MarkdownDocument({ assetLinks, text }: MarkdownDocumentProps) {
  return (
    <article className="markdown-body" dir="auto">
      <ReactMarkdown
        components={{
          a: ({ children, href, title }) => {
            const target = href && assetLinks ? skillAssetTarget(href, assetLinks) : null;
            return target ? <ContextLink title={title} to={target}>{children}</ContextLink> : <a href={href} title={title}>{children}</a>;
          },
          pre: ({ children, node, ...properties }) => {
            const metadata = node?.children.some((child) => child.type === "element" && child.properties["data-document-metadata"] === "");
            return metadata
              ? <details><summary>Document metadata (YAML)</summary><pre {...properties}>{children}</pre></details>
              : <pre {...properties}>{children}</pre>;
          }
        }}
        remarkPlugins={[remarkGfm, [remarkFrontmatter, { type: "yaml", marker: "-", anywhere: true }], documentMetadata]}
        skipHtml
      >
        {text}
      </ReactMarkdown>
    </article>
  );
}

export function skillAssetTarget(href: string, assets: ReadonlyMap<string, string>): string | null {
  try {
    const url = new URL(href, "https://skill-assets.invalid/");
    if (url.origin !== "https://skill-assets.invalid") return null;
    const path = decodeURIComponent(url.pathname.slice(1));
    const target = assets.get(path);
    return target ? `${target}${url.hash}` : null;
  } catch {
    return null;
  }
}
