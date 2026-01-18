/**
 * Markdown output formatter
 */

import type { ScanResult, Finding, FindingSeverity } from '../types.js';

/**
 * Format scan results as Markdown
 */
export function formatMarkdown(result: ScanResult): string {
  const lines: string[] = [];

  // Header
  lines.push('# Convex Security Scanner Report');
  lines.push('');

  // Metadata
  lines.push('## Summary');
  lines.push('');
  lines.push(`- **Scanner Version**: ${result.metadata.scannerVersion}`);
  lines.push(`- **Scan Time**: ${result.metadata.timestamp}`);
  lines.push(`- **Duration**: ${result.metadata.durationMs}ms`);
  lines.push(`- **Files Scanned**: ${result.metadata.filesScanned}`);
  lines.push(
    `- **Files with Findings**: ${result.metadata.filesWithFindings}`
  );
  lines.push(`- **Total Findings**: ${result.findings.length}`);
  lines.push(`- **Errors**: ${result.errors.length}`);
  lines.push('');

  // Rules Run
  if (result.metadata.rulesRun.length > 0) {
    lines.push('## Rules Executed');
    lines.push('');
    for (const ruleId of result.metadata.rulesRun) {
      lines.push(`- ${ruleId}`);
    }
    lines.push('');
  }

  // Findings by Severity
  if (result.findings.length > 0) {
    lines.push('## Findings by Severity');
    lines.push('');

    const severities: FindingSeverity[] = [
      'critical',
      'high',
      'medium',
      'low',
      'info',
    ];

    for (const severity of severities) {
      const findingsForSeverity = result.findings.filter(
        (f) => f.severity === severity
      );

      if (findingsForSeverity.length > 0) {
        lines.push(`### ${capitalize(severity)} (${findingsForSeverity.length})`);
        lines.push('');

        for (const finding of findingsForSeverity) {
          lines.push(formatFinding(finding));
          lines.push('');
        }
      }
    }
  } else {
    lines.push('## Findings');
    lines.push('');
    lines.push('✅ No security issues found!');
    lines.push('');
  }

  // File-by-File Breakdown
  if (result.findings.length > 0) {
    lines.push('## Findings by File');
    lines.push('');

    // Group findings by file
    const findingsByFile = new Map<string, Finding[]>();
    for (const finding of result.findings) {
      const existing = findingsByFile.get(finding.file) || [];
      existing.push(finding);
      findingsByFile.set(finding.file, existing);
    }

    // Sort files alphabetically
    const sortedFiles = Array.from(findingsByFile.keys()).sort();

    for (const file of sortedFiles) {
      const findings = findingsByFile.get(file)!;
      lines.push(`### ${file} (${findings.length})`);
      lines.push('');

      for (const finding of findings) {
        lines.push(formatFinding(finding));
        lines.push('');
      }
    }
  }

  // Errors
  if (result.errors.length > 0) {
    lines.push('## Errors');
    lines.push('');
    for (const error of result.errors) {
      lines.push(`### ${error.file}`);
      lines.push('');
      lines.push('```');
      lines.push(error.message);
      if (error.stack) {
        lines.push('');
        lines.push(error.stack);
      }
      lines.push('```');
      lines.push('');
    }
  }

  return lines.join('\n');
}

/**
 * Format a single finding
 */
function formatFinding(finding: Finding): string {
  const lines: string[] = [];

  lines.push(`#### \`${finding.rule}\` - ${finding.message}`);
  lines.push('');
  lines.push(`**Location**: \`${finding.file}:${finding.line}:${finding.column}\``);
  lines.push(`**Category**: ${finding.category}`);
  lines.push('');
  lines.push('**Remediation**:');
  lines.push('```');
  lines.push(finding.remediation);
  lines.push('```');
  lines.push('');
  lines.push('**Code Context**:');
  lines.push('```typescript');
  lines.push(finding.context);
  lines.push('```');

  return lines.join('\n');
}

/**
 * Capitalize first letter
 */
function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}
