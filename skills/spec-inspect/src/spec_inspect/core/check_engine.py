"""Check engine for running validation rules."""

from abc import ABC, abstractmethod
from typing import List

from ..models.issue import Issue
from ..models.parsed_document import ParsedSpecs


class CheckRule(ABC):
    """Abstract base class for check rules."""

    @abstractmethod
    def check(self, specs: ParsedSpecs) -> List[Issue]:
        """Execute the check rule.

        Args:
            specs: Parsed specification documents

        Returns:
            List of issues found by this rule
        """
        pass


class CheckEngine:
    """Engine for running check rules against specifications."""

    def __init__(self, rules: List[CheckRule]):
        """Initialize check engine with rules.

        Args:
            rules: List of check rules to execute
        """
        self.rules = rules

    def run_checks(self, specs: ParsedSpecs) -> List[Issue]:
        """Run all check rules against specifications.

        Args:
            specs: Parsed specification documents

        Returns:
            Aggregated list of all issues found
        """
        all_issues: List[Issue] = []

        for rule in self.rules:
            try:
                issues = rule.check(specs)
                all_issues.extend(issues)
            except Exception as e:
                # Log error but continue with other rules
                print(f"Error running rule {rule.__class__.__name__}: {e}")

        return all_issues

    def add_rule(self, rule: CheckRule) -> None:
        """Add a new check rule.

        Args:
            rule: Check rule to add
        """
        self.rules.append(rule)
