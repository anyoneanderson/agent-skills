"""Report generator for inspection results."""

from datetime import datetime
from typing import List, Dict
from collections import defaultdict

from ..models.issue import Issue, Severity


class ReportGenerator:
    """Generates inspection reports in various formats."""

    # ANSI color codes for terminal output
    COLORS = {
        Severity.CRITICAL: "\033[91m",  # Red
        Severity.WARNING: "\033[93m",   # Yellow
        Severity.INFO: "\033[94m",      # Blue
        "RESET": "\033[0m",
        "BOLD": "\033[1m",
    }

    # Icons for different severity levels
    ICONS = {
        Severity.CRITICAL: "⛔",
        Severity.WARNING: "⚠️",
        Severity.INFO: "ℹ️",
    }

    def generate_markdown(
        self,
        issues: List[Issue],
        project_name: str
    ) -> str:
        """Generate Markdown inspection report.

        Args:
            issues: List of detected issues
            project_name: Name of the inspected project

        Returns:
            Markdown-formatted report
        """
        # Categorize issues by severity
        categorized = self._categorize_issues(issues)

        # Count by severity
        critical_count = len(categorized[Severity.CRITICAL])
        warning_count = len(categorized[Severity.WARNING])
        info_count = len(categorized[Severity.INFO])

        # Build report
        lines = []
        lines.append(f"# spec-inspect レポート - {project_name}\n")
        lines.append("## 検査サマリー\n")
        lines.append(f"- 検査日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("- 検査対象: requirement.md, design.md, tasks.md")
        lines.append(f"- 検出問題数: **Critical: {critical_count}, Warning: {warning_count}, Info: {info_count}**\n")

        # Critical issues
        if critical_count > 0:
            lines.append("## ⛔ Critical Issues (実装ブロッカー)\n")
            for issue in categorized[Severity.CRITICAL]:
                lines.append(f"### [{issue.id}] {issue.title}\n")
                lines.append(f"- **ファイル**: `{issue.location}`")
                lines.append(f"- **詳細**: {issue.description}")
                if issue.suggestion:
                    lines.append(f"- **修正提案**: {issue.suggestion}")
                if issue.related_req_ids:
                    lines.append(f"- **関連要件**: {', '.join(issue.related_req_ids)}")
                lines.append("")

        # Warnings
        if warning_count > 0:
            lines.append("## ⚠️ Warnings (要確認事項)\n")
            for issue in categorized[Severity.WARNING]:
                lines.append(f"### [{issue.id}] {issue.title}\n")
                lines.append(f"- **ファイル**: `{issue.location}`")
                lines.append(f"- **詳細**: {issue.description}")
                if issue.suggestion:
                    lines.append(f"- **修正提案**: {issue.suggestion}")
                lines.append("")

        # Info
        if info_count > 0:
            lines.append("## ℹ️ Info (改善推奨)\n")
            for issue in categorized[Severity.INFO]:
                lines.append(f"### [{issue.id}] {issue.title}\n")
                lines.append(f"- **ファイル**: `{issue.location}`")
                lines.append(f"- **詳細**: {issue.description}")
                if issue.suggestion:
                    lines.append(f"- **修正提案**: {issue.suggestion}")
                lines.append("")

        return "\n".join(lines)

    def generate_console_output(self, issues: List[Issue]) -> str:
        """Generate colored console output.

        Args:
            issues: List of detected issues

        Returns:
            Colored terminal output
        """
        categorized = self._categorize_issues(issues)
        lines = []

        # Summary
        critical_count = len(categorized[Severity.CRITICAL])
        warning_count = len(categorized[Severity.WARNING])
        info_count = len(categorized[Severity.INFO])
        total = len(issues)

        lines.append(f"\n{self.COLORS['BOLD']}検査結果サマリー{self.COLORS['RESET']}")
        lines.append(f"  Total: {total} issues")
        lines.append(f"  {self.COLORS[Severity.CRITICAL]}⛔ Critical: {critical_count}{self.COLORS['RESET']}")
        lines.append(f"  {self.COLORS[Severity.WARNING]}⚠️  Warning: {warning_count}{self.COLORS['RESET']}")
        lines.append(f"  {self.COLORS[Severity.INFO]}ℹ️  Info: {info_count}{self.COLORS['RESET']}\n")

        # Critical issues
        if critical_count > 0:
            lines.append(f"{self.COLORS[Severity.CRITICAL]}{self.COLORS['BOLD']}⛔ CRITICAL ISSUES{self.COLORS['RESET']}")
            for issue in categorized[Severity.CRITICAL]:
                lines.append(self._format_console_issue(issue, Severity.CRITICAL))

        # Warnings
        if warning_count > 0:
            lines.append(f"\n{self.COLORS[Severity.WARNING]}{self.COLORS['BOLD']}⚠️  WARNINGS{self.COLORS['RESET']}")
            for issue in categorized[Severity.WARNING]:
                lines.append(self._format_console_issue(issue, Severity.WARNING))

        # Info
        if info_count > 0:
            lines.append(f"\n{self.COLORS[Severity.INFO]}{self.COLORS['BOLD']}ℹ️  INFO{self.COLORS['RESET']}")
            for issue in categorized[Severity.INFO]:
                lines.append(self._format_console_issue(issue, Severity.INFO))

        return "\n".join(lines)

    def _categorize_issues(self, issues: List[Issue]) -> Dict[Severity, List[Issue]]:
        """Categorize issues by severity.

        Args:
            issues: List of all issues

        Returns:
            Dictionary mapping severity to list of issues
        """
        categorized: Dict[Severity, List[Issue]] = defaultdict(list)
        for issue in issues:
            categorized[issue.severity].append(issue)
        return categorized

    def _format_console_issue(self, issue: Issue, severity: Severity) -> str:
        """Format a single issue for console output.

        Args:
            issue: Issue to format
            severity: Severity level for coloring

        Returns:
            Formatted issue string
        """
        color = self.COLORS[severity]
        reset = self.COLORS['RESET']

        lines = []
        lines.append(f"\n{color}[{issue.id}] {issue.title}{reset}")
        lines.append(f"  📄 {issue.location}")
        lines.append(f"  {issue.description}")
        if issue.suggestion:
            lines.append(f"  💡 {issue.suggestion}")

        return "\n".join(lines)
