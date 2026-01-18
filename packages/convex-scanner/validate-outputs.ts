/**
 * Manual validation script to test JSON and Markdown outputs
 */
import { resolve } from 'node:path';
import { scanConvex } from './src/scanner/static-scanner.js';
import { formatJson } from './src/output/json.js';
import { formatMarkdown } from './src/output/markdown.js';

async function main() {
  const valetPath = resolve(__dirname, '../valet');

  console.log('Scanning packages/valet/convex...\n');

  const result = await scanConvex(valetPath, {
    convexDir: './convex',
  });

  console.log('=== JSON Output ===\n');
  const jsonOutput = formatJson(result);
  console.log(jsonOutput);

  console.log('\n\n=== Markdown Output ===\n');
  const markdownOutput = formatMarkdown(result);
  console.log(markdownOutput);
}

main().catch(console.error);
