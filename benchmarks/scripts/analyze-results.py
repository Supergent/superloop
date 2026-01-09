#!/usr/bin/env python3
"""
Analyze benchmark results and generate comparison report
Usage: ./analyze-results.py [--output report.md]
"""

import json
import glob
import argparse
from pathlib import Path
from collections import defaultdict
from statistics import mean, median, stdev
import sys

def load_results(results_dir="benchmark-results"):
    """Load all JSON result files"""
    results = []
    for json_file in glob.glob(f"{results_dir}/*.json"):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                results.append(data)
        except Exception as e:
            print(f"Warning: Failed to load {json_file}: {e}", file=sys.stderr)
    return results

def group_by_scenario(results):
    """Group results by scenario"""
    grouped = defaultdict(lambda: {"vanilla": [], "glm": []})
    for result in results:
        scenario = result.get("scenario")
        system = result.get("system")
        if scenario and system:
            grouped[scenario][system].append(result)
    return grouped

def calculate_stats(values):
    """Calculate mean, median, stdev for a list of values"""
    if not values:
        return {"mean": 0, "median": 0, "stdev": 0, "n": 0}
    return {
        "mean": mean(values),
        "median": median(values),
        "stdev": stdev(values) if len(values) > 1 else 0,
        "n": len(values)
    }

def analyze_scenario(scenario_name, vanilla_results, glm_results):
    """Analyze a single scenario comparing vanilla vs GLM"""
    analysis = {
        "scenario": scenario_name,
        "vanilla": {},
        "glm": {},
        "comparison": {}
    }

    # Duration
    vanilla_durations = [r["duration_seconds"] for r in vanilla_results]
    glm_durations = [r["duration_seconds"] for r in glm_results]

    analysis["vanilla"]["duration"] = calculate_stats(vanilla_durations)
    analysis["glm"]["duration"] = calculate_stats(glm_durations)

    if analysis["vanilla"]["duration"]["median"] > 0:
        speedup = analysis["vanilla"]["duration"]["median"] / analysis["glm"]["duration"]["median"]
        analysis["comparison"]["speedup"] = speedup
    else:
        analysis["comparison"]["speedup"] = 0

    # Edit metrics (if applicable)
    if vanilla_results and "edit_metrics" in vanilla_results[0]:
        vanilla_files = [r["edit_metrics"].get("files_modified", 0) for r in vanilla_results]
        glm_files = [r["edit_metrics"].get("files_modified", 0) for r in glm_results]

        vanilla_lines = [r["edit_metrics"].get("lines_changed", 0) for r in vanilla_results]
        glm_lines = [r["edit_metrics"].get("lines_changed", 0) for r in glm_results]

        analysis["vanilla"]["files_modified"] = calculate_stats(vanilla_files)
        analysis["glm"]["files_modified"] = calculate_stats(glm_files)

        analysis["vanilla"]["lines_changed"] = calculate_stats(vanilla_lines)
        analysis["glm"]["lines_changed"] = calculate_stats(glm_lines)

        # Validation success rate
        vanilla_validated = sum(1 for r in vanilla_results if r["edit_metrics"].get("validation_passed", False))
        glm_validated = sum(1 for r in glm_results if r["edit_metrics"].get("validation_passed", False))

        analysis["vanilla"]["validation_success_rate"] = vanilla_validated / len(vanilla_results) if vanilla_results else 0
        analysis["glm"]["validation_success_rate"] = glm_validated / len(glm_results) if glm_results else 0

    return analysis

def generate_markdown_report(all_analyses):
    """Generate markdown report"""
    md = ["# Claude-Code-GLM vs Vanilla Benchmark Results\n"]
    md.append(f"*Generated from {sum(a['vanilla']['duration']['n'] + a['glm']['duration']['n'] for a in all_analyses)} total test runs*\n")

    # Executive Summary
    md.append("## Executive Summary\n")

    overall_speedups = [a["comparison"]["speedup"] for a in all_analyses if a["comparison"]["speedup"] > 0]
    if overall_speedups:
        avg_speedup = mean(overall_speedups)
        md.append(f"- **Average Speedup:** {avg_speedup:.2f}x (GLM vs Vanilla)")

        faster_count = sum(1 for s in overall_speedups if s > 1.0)
        md.append(f"- **GLM Faster:** {faster_count}/{len(overall_speedups)} scenarios")

        if avg_speedup > 1.2:
            md.append(f"- **Verdict:** GLM shows significant performance improvement ({avg_speedup:.1f}x faster on average)")
        elif avg_speedup > 1.0:
            md.append(f"- **Verdict:** GLM shows modest performance improvement ({avg_speedup:.1f}x faster on average)")
        else:
            md.append(f"- **Verdict:** Vanilla performs better ({1/avg_speedup:.1f}x faster than GLM)")
    md.append("")

    # Detailed Results
    md.append("## Detailed Results by Scenario\n")

    for analysis in all_analyses:
        scenario = analysis["scenario"]
        md.append(f"### {scenario.replace('_', ' ').title()}\n")

        # Duration comparison
        v_dur = analysis["vanilla"]["duration"]
        g_dur = analysis["glm"]["duration"]
        speedup = analysis["comparison"]["speedup"]

        md.append("#### Time Performance")
        md.append(f"- **Vanilla:** {v_dur['median']:.2f}s (median), {v_dur['stdev']:.2f}s stdev, n={v_dur['n']}")
        md.append(f"- **GLM:** {g_dur['median']:.2f}s (median), {g_dur['stdev']:.2f}s stdev, n={g_dur['n']}")
        md.append(f"- **Speedup:** {speedup:.2f}x {'✓' if speedup > 1.0 else '✗'}\n")

        # Edit metrics if present
        if "files_modified" in analysis["vanilla"]:
            md.append("#### Edit Metrics")

            v_files = analysis["vanilla"]["files_modified"]
            g_files = analysis["glm"]["files_modified"]
            md.append(f"- **Files Modified:** Vanilla {v_files['median']:.0f}, GLM {g_files['median']:.0f}")

            v_lines = analysis["vanilla"]["lines_changed"]
            g_lines = analysis["glm"]["lines_changed"]
            md.append(f"- **Lines Changed:** Vanilla {v_lines['median']:.0f}, GLM {g_lines['median']:.0f}")

            v_val = analysis["vanilla"]["validation_success_rate"]
            g_val = analysis["glm"]["validation_success_rate"]
            md.append(f"- **Validation Success:** Vanilla {v_val*100:.0f}%, GLM {g_val*100:.0f}%\n")

        md.append("---\n")

    # Statistical Summary
    md.append("## Statistical Summary\n")
    md.append("| Scenario | Vanilla (median) | GLM (median) | Speedup | Winner |")
    md.append("|----------|------------------|--------------|---------|--------|")

    for analysis in all_analyses:
        scenario = analysis["scenario"]
        v_time = analysis["vanilla"]["duration"]["median"]
        g_time = analysis["glm"]["duration"]["median"]
        speedup = analysis["comparison"]["speedup"]
        winner = "GLM" if speedup > 1.0 else "Vanilla"
        md.append(f"| {scenario} | {v_time:.2f}s | {g_time:.2f}s | {speedup:.2f}x | **{winner}** |")

    md.append("")

    # Recommendations
    md.append("## Recommendations\n")
    if avg_speedup > 1.2:
        md.append("- **Strong recommendation** to use Claude-Code-GLM for production workflows")
        md.append("- The Mantic semantic search and Relace instant edit provide significant speedups")
    elif avg_speedup > 1.0:
        md.append("- **Moderate recommendation** to use Claude-Code-GLM")
        md.append("- Benefits vary by scenario; consider for complex multi-file edits")
    else:
        md.append("- Vanilla Claude Code performs better in these benchmarks")
        md.append("- Further investigation needed into GLM overhead")

    md.append("")
    md.append("## Next Steps\n")
    md.append("- [ ] Analyze tool call sequences for efficiency patterns")
    md.append("- [ ] Measure token usage and costs")
    md.append("- [ ] Test on additional codebases (Linux kernel, Chromium, etc.)")
    md.append("- [ ] Profile Orb VM overhead vs native execution")

    return "\n".join(md)

def main():
    parser = argparse.ArgumentParser(description="Analyze benchmark results")
    parser.add_argument("--output", default="benchmark-report.md", help="Output markdown file")
    parser.add_argument("--results-dir", default="benchmark-results", help="Directory containing JSON results")
    args = parser.parse_args()

    print(f"Loading results from {args.results_dir}...")
    results = load_results(args.results_dir)
    print(f"Loaded {len(results)} result files")

    if not results:
        print("Error: No results found!", file=sys.stderr)
        sys.exit(1)

    grouped = group_by_scenario(results)
    print(f"Found {len(grouped)} scenarios")

    all_analyses = []
    for scenario_name in sorted(grouped.keys()):
        vanilla = grouped[scenario_name]["vanilla"]
        glm = grouped[scenario_name]["glm"]

        if not vanilla or not glm:
            print(f"Warning: Skipping {scenario_name} (missing data for vanilla or glm)", file=sys.stderr)
            continue

        analysis = analyze_scenario(scenario_name, vanilla, glm)
        all_analyses.append(analysis)

    print(f"Analyzed {len(all_analyses)} scenarios")

    # Generate report
    report = generate_markdown_report(all_analyses)

    with open(args.output, 'w') as f:
        f.write(report)

    print(f"Report written to: {args.output}")
    print("\nPreview:")
    print("=" * 80)
    # Print first 20 lines
    for line in report.split('\n')[:20]:
        print(line)
    print("...")

if __name__ == "__main__":
    main()
