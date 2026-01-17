/**
 * Parsers for Mole CLI command outputs
 * Converts raw command output (JSON or text) into typed TypeScript objects
 */

import type {
  MoleStatusMetrics,
  MoleAnalyzeResult,
  MoleCleanResult,
  MoleUninstallResult,
  MoleOptimizeResult,
  MolePurgeResult,
  MoleInstallerResult,
  MoleError,
} from './moleTypes';

// ============================================================================
// mo status --json
// ============================================================================

export function parseStatusJson(jsonOutput: string): MoleStatusMetrics {
  try {
    const data = JSON.parse(jsonOutput);

    // The actual JSON structure from mo status --json
    // We'll adapt to whatever structure the Go binary returns
    return {
      cpu: {
        usage: data.cpu?.usage || data.cpu_usage || 0,
        cores: data.cpu?.cores || data.cpu_cores || 1,
        temperature: data.cpu?.temperature || data.cpu_temp,
      },
      memory: {
        used: data.memory?.used || data.mem_used || 0,
        total: data.memory?.total || data.mem_total || 0,
        available: data.memory?.available || data.mem_available || 0,
        percentage: data.memory?.percentage || data.mem_percentage || 0,
        swap: data.memory?.swap || data.swap
          ? {
              used: data.memory?.swap?.used || data.swap?.used || 0,
              total: data.memory?.swap?.total || data.swap?.total || 0,
            }
          : undefined,
      },
      disk: {
        used: data.disk?.used || data.disk_used || 0,
        total: data.disk?.total || data.disk_total || 0,
        available: data.disk?.available || data.disk_available || 0,
        percentage: data.disk?.percentage || data.disk_percentage || 0,
        mountPoint: data.disk?.mountPoint || data.disk_mount || '/',
      },
      network: {
        bytesReceived: data.network?.bytesReceived || data.net_rx || 0,
        bytesSent: data.network?.bytesSent || data.net_tx || 0,
        packetsReceived: data.network?.packetsReceived || data.net_rx_packets || 0,
        packetsSent: data.network?.packetsSent || data.net_tx_packets || 0,
      },
      timestamp: data.timestamp || Date.now(),
    };
  } catch (error) {
    throw createParseError('status', error);
  }
}

// ============================================================================
// mo analyze (text output)
// ============================================================================

export function parseAnalyzeOutput(textOutput: string): MoleAnalyzeResult {
  try {
    const directories: any[] = [];
    let totalSize = 0;
    let scanPath = '/';

    // Parse text output line by line
    // Expected format:
    // 1.2 GB  /Users/username/Library/Caches
    // 800 MB  /Users/username/Downloads
    // etc.

    const lines = textOutput.trim().split('\n');
    for (const line of lines) {
      const match = line.match(/^([\d.]+)\s*(B|KB|MB|GB|TB)\s+(.+)$/);
      if (match) {
        const [, sizeStr, unit, path] = match;
        const size = parseSizeToBytes(parseFloat(sizeStr), unit);
        totalSize += size;

        directories.push({
          path: path.trim(),
          size,
          percentage: 0, // Will calculate after we know total
          fileCount: 0, // Not available from text output
        });
      }
    }

    // Calculate percentages
    directories.forEach((dir) => {
      dir.percentage = totalSize > 0 ? (dir.size / totalSize) * 100 : 0;
    });

    return {
      directories,
      totalSize,
      scanPath,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('analyze', error);
  }
}

// ============================================================================
// mo clean (text output)
// ============================================================================

export function parseCleanOutput(textOutput: string, isDryRun: boolean): MoleCleanResult {
  try {
    let itemsRemoved = 0;
    let spaceRecovered = 0;
    const categories: any[] = [];
    let currentCategory: any = null;

    const lines = textOutput.trim().split('\n');

    for (const line of lines) {
      // Look for category headers (e.g., "System Caches:")
      if (line.match(/^[A-Z].*:$/)) {
        if (currentCategory) {
          categories.push(currentCategory);
        }
        currentCategory = {
          name: line.replace(':', ''),
          itemsRemoved: 0,
          spaceRecovered: 0,
          files: [],
        };
      }
      // Look for file entries or summary lines
      else if (line.includes('removed') || line.includes('freed') || line.includes('recovered')) {
        const sizeMatch = line.match(/([\d.]+)\s*(B|KB|MB|GB|TB)/);
        if (sizeMatch) {
          const size = parseSizeToBytes(parseFloat(sizeMatch[1]), sizeMatch[2]);
          spaceRecovered += size;
          if (currentCategory) {
            currentCategory.spaceRecovered += size;
          }
        }

        const itemMatch = line.match(/(\d+)\s+items?/);
        if (itemMatch) {
          const count = parseInt(itemMatch[1], 10);
          itemsRemoved += count;
          if (currentCategory) {
            currentCategory.itemsRemoved += count;
          }
        }
      }
    }

    if (currentCategory) {
      categories.push(currentCategory);
    }

    return {
      itemsRemoved,
      spaceRecovered,
      categories,
      dryRun: isDryRun,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('clean', error);
  }
}

// ============================================================================
// mo uninstall (text output)
// ============================================================================

export function parseUninstallOutput(appName: string, textOutput: string): MoleUninstallResult {
  try {
    const itemsRemoved: any[] = [];
    let spaceRecovered = 0;
    const success = !textOutput.toLowerCase().includes('error') && !textOutput.toLowerCase().includes('failed');

    const lines = textOutput.trim().split('\n');

    for (const line of lines) {
      // Look for removed items
      if (line.includes('Removed') || line.includes('Deleted')) {
        const pathMatch = line.match(/[/~].+/);
        if (pathMatch) {
          const path = pathMatch[0];
          let type: any = 'other';

          if (path.includes('.app')) type = 'application';
          else if (path.includes('Caches')) type = 'cache';
          else if (path.includes('Preferences')) type = 'preferences';
          else if (path.includes('Login')) type = 'login_items';

          itemsRemoved.push({
            type,
            path,
            size: 0, // Size not always provided in text output
          });
        }
      }

      // Look for total size
      const sizeMatch = line.match(/([\d.]+)\s*(B|KB|MB|GB|TB)\s+recovered/i);
      if (sizeMatch) {
        spaceRecovered = parseSizeToBytes(parseFloat(sizeMatch[1]), sizeMatch[2]);
      }
    }

    return {
      appName,
      success,
      spaceRecovered,
      itemsRemoved,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('uninstall', error);
  }
}

// ============================================================================
// mo optimize (text output)
// ============================================================================

export function parseOptimizeOutput(textOutput: string, isDryRun: boolean): MoleOptimizeResult {
  try {
    const tasksCompleted: any[] = [];
    const requiresSudo = textOutput.includes('sudo') || textOutput.includes('administrator');

    const lines = textOutput.trim().split('\n');

    for (const line of lines) {
      // Look for task completion indicators
      if (line.includes('✓') || line.includes('✔') || line.includes('Done') || line.includes('Complete')) {
        tasksCompleted.push({
          name: line.replace(/[✓✔]/g, '').trim(),
          description: '',
          success: true,
        });
      } else if (line.includes('✗') || line.includes('Failed') || line.includes('Error')) {
        tasksCompleted.push({
          name: line.replace(/[✗]/g, '').trim(),
          description: '',
          success: false,
          error: line,
        });
      }
    }

    return {
      tasksCompleted,
      dryRun: isDryRun,
      requiresSudo,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('optimize', error);
  }
}

// ============================================================================
// mo purge (text output)
// ============================================================================

export function parsePurgeOutput(textOutput: string, isDryRun: boolean): MolePurgeResult {
  try {
    const artifactsFound: any[] = [];
    let totalSize = 0;
    let spaceRecovered = 0;

    const lines = textOutput.trim().split('\n');

    for (const line of lines) {
      // Look for artifact paths (node_modules, build, etc.)
      const pathMatch = line.match(/([/~].+(?:node_modules|build|dist|target|\.next))/);
      if (pathMatch) {
        const path = pathMatch[1];
        let type: any = 'other';

        if (path.includes('node_modules')) type = 'node_modules';
        else if (path.includes('build')) type = 'build';
        else if (path.includes('.next')) type = '.next';
        else if (path.includes('dist')) type = 'dist';
        else if (path.includes('target')) type = 'target';

        const sizeMatch = line.match(/([\d.]+)\s*(B|KB|MB|GB|TB)/);
        const size = sizeMatch ? parseSizeToBytes(parseFloat(sizeMatch[1]), sizeMatch[2]) : 0;

        artifactsFound.push({
          type,
          path,
          size,
          projectName: extractProjectName(path),
        });

        totalSize += size;
        if (!isDryRun) {
          spaceRecovered += size;
        }
      }
    }

    return {
      artifactsFound,
      totalSize,
      spaceRecovered,
      dryRun: isDryRun,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('purge', error);
  }
}

// ============================================================================
// mo installer (text output)
// ============================================================================

export function parseInstallerOutput(textOutput: string, isDryRun: boolean): MoleInstallerResult {
  try {
    const installersFound: any[] = [];
    let totalSize = 0;
    let spaceRecovered = 0;

    const lines = textOutput.trim().split('\n');

    for (const line of lines) {
      // Look for installer files (.dmg, .pkg, .zip, etc.)
      const match = line.match(/([/~].+\.(dmg|pkg|zip|app|tar|gz))/i);
      if (match) {
        const path = match[1];
        const type = path.match(/\.(dmg|pkg|zip|app|tar|gz)$/i)?.[1] || 'unknown';

        const sizeMatch = line.match(/([\d.]+)\s*(B|KB|MB|GB|TB)/);
        const size = sizeMatch ? parseSizeToBytes(parseFloat(sizeMatch[1]), sizeMatch[2]) : 0;

        installersFound.push({
          path,
          size,
          type,
          name: path.split('/').pop() || '',
        });

        totalSize += size;
        if (!isDryRun) {
          spaceRecovered += size;
        }
      }
    }

    return {
      installersFound,
      totalSize,
      spaceRecovered,
      dryRun: isDryRun,
      timestamp: Date.now(),
    };
  } catch (error) {
    throw createParseError('installer', error);
  }
}

// ============================================================================
// Helper functions
// ============================================================================

function parseSizeToBytes(value: number, unit: string): number {
  const units: Record<string, number> = {
    B: 1,
    KB: 1024,
    MB: 1024 * 1024,
    GB: 1024 * 1024 * 1024,
    TB: 1024 * 1024 * 1024 * 1024,
  };

  return value * (units[unit.toUpperCase()] || 1);
}

function extractProjectName(path: string): string {
  // Extract project name from path like /Users/name/Projects/myproject/node_modules
  const parts = path.split('/');
  const artifactIndex = parts.findIndex((p) =>
    ['node_modules', 'build', 'dist', 'target', '.next'].includes(p)
  );

  if (artifactIndex > 0) {
    return parts[artifactIndex - 1];
  }

  return '';
}

function createParseError(command: string, error: unknown): MoleError {
  return {
    command,
    message: error instanceof Error ? error.message : 'Unknown parsing error',
    stderr: error instanceof Error ? error.stack : undefined,
  };
}

// ============================================================================
// Error detection
// ============================================================================

export function hasError(output: string): boolean {
  const errorIndicators = [
    'error:',
    'failed:',
    'permission denied',
    'not found',
    'could not',
    'cannot',
  ];

  const lowerOutput = output.toLowerCase();
  return errorIndicators.some((indicator) => lowerOutput.includes(indicator));
}

export function extractErrorMessage(output: string): string {
  const lines = output.split('\n');

  for (const line of lines) {
    if (hasError(line)) {
      return line.trim();
    }
  }

  return 'An unknown error occurred';
}
