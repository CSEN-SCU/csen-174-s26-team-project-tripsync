#!/usr/bin/env node
/**
 * Export markdown files with mermaid diagrams to PDF via headless Chrome.
 * Usage: node scripts/export-markdown-pdf.mjs docs/foo.md [docs/bar.md ...]
 */
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { tmpdir } from 'node:os';
import { marked } from 'marked';
import puppeteer from 'puppeteer';

marked.use({ gfm: true, breaks: false });

function markdownToBodyHtml(md) {
  const chunks = [];
  const re = /```mermaid\n([\s\S]*?)```/g;
  let last = 0;
  let match;

  while ((match = re.exec(md)) !== null) {
    chunks.push(marked.parse(md.slice(last, match.index)));
    chunks.push(`<div class="mermaid">${match[1].trim()}</div>`);
    last = re.lastIndex;
  }

  chunks.push(marked.parse(md.slice(last)));
  return chunks.join('\n');
}

function wrapHtml(body) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Export</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 11pt;
      line-height: 1.45;
      color: #111;
      max-width: 920px;
      margin: 0 auto;
      padding: 28px 32px;
    }
    h1 { font-size: 21pt; border-bottom: 1px solid #ddd; padding-bottom: 8px; }
    h2 { font-size: 15pt; margin-top: 1.4em; page-break-after: avoid; }
    h3 { font-size: 12pt; page-break-after: avoid; }
    p, li { orphans: 3; widows: 3; }
    table { border-collapse: collapse; width: 100%; font-size: 8.5pt; margin: 1em 0; page-break-inside: avoid; }
    th, td { border: 1px solid #ccc; padding: 5px 7px; text-align: left; vertical-align: top; }
    th { background: #f5f5f5; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 9pt; background: #f4f4f4; padding: 1px 4px; border-radius: 3px; }
    pre { background: #f8f8f8; padding: 10px 12px; border-radius: 6px; overflow-x: auto; font-size: 9pt; }
    pre code { background: none; padding: 0; }
    hr { border: none; border-top: 1px solid #ddd; margin: 1.8em 0; }
    .mermaid { margin: 18px 0; text-align: center; page-break-inside: avoid; }
    .mermaid svg { max-width: 100%; height: auto; }
  </style>
</head>
<body>
${body}
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({ startOnLoad: false, theme: "default", securityLevel: "loose" });
  mermaid.run({ querySelector: ".mermaid" }).then(function () {
    document.body.dataset.renderDone = "true";
  }).catch(function (err) {
    console.error(err);
    document.body.dataset.renderDone = "error";
  });
</script>
</body>
</html>`;
}

async function exportPdf(mdPath) {
  const md = readFileSync(mdPath, 'utf8');
  const pdfPath = mdPath.replace(/\.md$/i, '.pdf');
  const html = wrapHtml(markdownToBodyHtml(md));
  const tmpHtml = join(tmpdir(), `md-export-${basename(mdPath, '.md')}-${Date.now()}.html`);
  writeFileSync(tmpHtml, html, 'utf8');

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  try {
    const page = await browser.newPage();
    await page.goto(`file://${tmpHtml}`, { waitUntil: 'networkidle0', timeout: 120000 });
    await page.waitForFunction(
      () => document.body.dataset.renderDone === 'true' || document.body.dataset.renderDone === 'error',
      { timeout: 120000 },
    );

    const mermaidCount = await page.evaluate(() => document.querySelectorAll('.mermaid').length);
    if (mermaidCount > 0) {
      await page.waitForFunction(
        () => {
          const blocks = document.querySelectorAll('.mermaid');
          return Array.from(blocks).every((b) => b.querySelector('svg'));
        },
        { timeout: 120000 },
      );
    }

    await page.pdf({
      path: pdfPath,
      format: 'Letter',
      printBackground: true,
      margin: { top: '0.55in', bottom: '0.55in', left: '0.65in', right: '0.65in' },
    });

    console.log(`Wrote ${pdfPath}`);
  } finally {
    await browser.close();
    try {
      unlinkSync(tmpHtml);
    } catch {
      // ignore
    }
  }
}

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: node scripts/export-markdown-pdf.mjs <file.md> [...]');
  process.exit(1);
}

for (const file of files) {
  await exportPdf(file);
}
