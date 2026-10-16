import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { MarkdownDocument } from "../src/markdown/markdown-document.js";
import { MarkdownPreview } from "../src/markdown/markdown-preview.js";

function render(text: string, assetLinks?: ReadonlyMap<string, string>) {
  return renderToStaticMarkup(<MemoryRouter><MarkdownDocument assetLinks={assetLinks} text={text} /></MemoryRouter>);
}

test("leading YAML remains inspectable metadata rather than headings or discarded text", () => {
  const markup = render("---\nname: example\ndescription: A deliberately long description.\n---\n\n# Document title\n\nBody text.");
  assert.match(markup, /<details><summary>Document metadata \(YAML\)<\/summary><pre><code[^>]*>/);
  assert.match(markup, /name: example\ndescription: A deliberately long description\./);
  assert.match(markup, /<h1>Document title<\/h1>/);
  assert.match(markup, /<p>Body text\.<\/p>/);
  assert.doesNotMatch(markup, /<h[1-6]>name:|<details open/);
});

test("the prefaced Skill form in the reported issue does not create an oversized metadata heading", () => {
  const description = "Long metadata value. ".repeat(200);
  const text = `Preserved introductory context.\n\n---\nname: example\ndescription: ${description}\n---\n\n# Author content\n\nCurrent instructions.`;
  const markup = render(text);
  assert.match(markup, /<p>Preserved introductory context\.<\/p>\n<details>/);
  assert.match(markup, /Document metadata \(YAML\)/);
  assert.match(markup, /<h1>Author content<\/h1>/);
  assert.doesNotMatch(markup, /<h2>name:/);
  assert.ok(markup.includes(description));
  assert.ok(text.includes(`description: ${description}\n---`));
});

test("ordinary thematic breaks, setext headings and reference links retain Markdown meaning", () => {
  const markup = render("Introduction.\n\n---\n\nMiddle [guide][ref].\n\n---\n\nFinal title\n-----------\n\n[ref]: https://example.org/guide");
  assert.equal((markup.match(/<hr\/>/g) ?? []).length, 2);
  assert.match(markup, /<h2>Final title<\/h2>/);
  assert.match(markup, /href="https:\/\/example.org\/guide">guide<\/a>/);
  assert.doesNotMatch(markup, /Document metadata|<details>/);
});

test("later delimiter blocks are normal Markdown even when a document also has metadata", () => {
  const markup = render("---\nname: example\n---\n\n# Heading\n\n---\n\nSection text\n\n---\n\nAfter.");
  assert.equal((markup.match(/<details>/g) ?? []).length, 1);
  assert.equal((markup.match(/<hr\/>/g) ?? []).length, 2);
  assert.match(markup, /<p>Section text<\/p>/);
});

test("an ordinary document may begin with a horizontal rule without becoming hidden metadata", () => {
  const markup = render("---\n\nOpening prose.\n\n---\n\nMore prose.");
  assert.equal((markup.match(/<hr\/>/g) ?? []).length, 2);
  assert.match(markup, /<p>Opening prose\.<\/p>/);
  assert.doesNotMatch(markup, /<details>/);
});

test("metadata cannot break out of its code fence or consume body references and GFM footnotes", () => {
  const markup = render("Preface.\n\n---\nname: example\ndescription: |\n  ```\n  <script>unsafe()</script>\n  ```\n---\n\nRead [guide][ref] and note[^one].\n\n[ref]: https://example.org/guide\n\n[^one]: Footnote body.");
  assert.equal((markup.match(/<details>/g) ?? []).length, 1);
  assert.match(markup, /&lt;script&gt;unsafe\(\)&lt;\/script&gt;/);
  assert.match(markup, /href="https:\/\/example.org\/guide">guide<\/a>/);
  assert.match(markup, /Footnote body\./);
  assert.doesNotMatch(markup, /<script>/);
});

test("metadata handles CRLF and comments while fenced examples stay literal code", () => {
  const markup = render("Preface.\r\n\r\n---\r\n# metadata comment\r\nname: example\r\n---\r\n\r\n```yaml\n---\nname: code example\n---\n```");
  assert.equal((markup.match(/Document metadata \(YAML\)/g) ?? []).length, 1);
  assert.match(markup, /# metadata comment\r?\nname: example/);
  assert.match(markup, /---\nname: code example\n---/);
});

test("GFM keeps native tables, checkboxes and code without UI framework classes", () => {
  const markup = render("| State | Owner |\n| --- | --- |\n| ready | agent |\n\n- [x] checked\n\n~~obsolete~~\n\n`inline code`\n\n```ruby\nputs 'hello'\n```");
  assert.match(markup, /<table>/);
  assert.match(markup, /<th>State<\/th>/);
  assert.match(markup, /type="checkbox"[^>]*disabled=""[^>]*checked=""/);
  assert.match(markup, /<del>obsolete<\/del>/);
  assert.match(markup, /class="language-ruby"/);
  assert.doesNotMatch(markup, /table-striped|table-bordered|form-check-input|text-bg-/);
});

test("HTML and unsafe URLs remain inert in body and metadata", () => {
  const markup = render("---\nname: '<script>metadata()</script>'\n---\n\n<script>body()</script>\n\n<style>body {color:red}</style>\n\n[unsafe](javascript:alert(1))\n\n[safe](https://example.org)");
  assert.match(markup, /&lt;script&gt;metadata\(\)&lt;\/script&gt;/);
  assert.match(markup, /href="https:\/\/example.org"/);
  assert.doesNotMatch(markup, /<script|<style|javascript:/);
});

test("manifest asset links retain React Router destinations in the document renderer", () => {
  const destination = "/projects/project:work/skills/example/assets/references/guide.md";
  const markup = render("Read [the guide](references/guide.md#section).", new Map([["references/guide.md", destination]]));
  assert.match(markup, new RegExp(`href="${destination}#section"`));
});

test("the preview exposes a keyboard-scrollable isolation host, not a second global stylesheet", () => {
  const markup = renderToStaticMarkup(<MarkdownPreview text="# Body" />);
  assert.match(markup, /aria-label="Markdown preview"/);
  assert.match(markup, /role="region" tabindex="0"/);
  assert.match(markup, /data-markdown-preview=""[^>]*style="all:initial;display:block"/);
  assert.doesNotMatch(markup, /<style|<h1>/);
  const entry = readFileSync(new URL("../../src/main.tsx", import.meta.url), "utf8");
  assert.match(entry, /github-markdown-light\.css\?inline/);
  assert.match(entry, /MarkdownStylesContext\.Provider value=\{markdownStyles\}/);
});
