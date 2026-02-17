"""Requirement ID validation rule."""

from typing import List, Set
import re

from ..core.check_engine import CheckRule
from ..models.issue import Issue, Severity, Location
from ..models.parsed_document import ParsedSpecs


class RequirementIDValidator(CheckRule):
    """Validates requirement ID references across documents."""

    def check(self, specs: ParsedSpecs) -> List[Issue]:
        """Check requirement ID consistency.

        Validates:
        1. References in design.md and tasks.md exist in requirement.md
        2. Detects unreferenced requirements (Info level)

        Args:
            specs: Parsed specification documents

        Returns:
            List of issues found
        """
        issues: List[Issue] = []
        issue_counter = {"CRITICAL": 1, "INFO": 1}

        # Get defined requirement IDs from requirement.md
        defined_ids = specs.requirement.requirement_ids

        # Get referenced IDs from design.md and tasks.md
        design_refs = specs.design.requirement_ids
        tasks_refs = specs.tasks.requirement_ids
        all_refs = design_refs | tasks_refs

        # Check for non-existent requirement ID references (CRITICAL)
        for ref_id in design_refs:
            if ref_id not in defined_ids:
                location = self._find_location(ref_id, specs.design.raw_text, "design.md")
                issues.append(Issue(
                    id=f"CRITICAL-{issue_counter['CRITICAL']:03d}",
                    severity=Severity.CRITICAL,
                    title=f"Requirement ID {ref_id} does not exist",
                    description=f"{ref_id} is referenced in design.md but not defined in requirement.md",
                    location=location,
                    suggestion=f"Add {ref_id} to requirement.md or fix the reference in design.md",
                    related_req_ids=[ref_id]
                ))
                issue_counter["CRITICAL"] += 1

        for ref_id in tasks_refs:
            if ref_id not in defined_ids:
                location = self._find_location(ref_id, specs.tasks.raw_text, "tasks.md")
                issues.append(Issue(
                    id=f"CRITICAL-{issue_counter['CRITICAL']:03d}",
                    severity=Severity.CRITICAL,
                    title=f"Requirement ID {ref_id} does not exist",
                    description=f"{ref_id} is referenced in tasks.md but not defined in requirement.md",
                    location=location,
                    suggestion=f"Add {ref_id} to requirement.md or fix the reference in tasks.md",
                    related_req_ids=[ref_id]
                ))
                issue_counter["CRITICAL"] += 1

        # Check for unreferenced requirements (INFO)
        for req_id in defined_ids:
            if req_id not in all_refs:
                location = self._find_location(req_id, specs.requirement.raw_text, "requirement.md")
                issues.append(Issue(
                    id=f"INFO-{issue_counter['INFO']:03d}",
                    severity=Severity.INFO,
                    title=f"Requirement ID {req_id} is not referenced",
                    description=f"{req_id} is defined but not referenced in design.md or tasks.md",
                    location=location,
                    suggestion="Is this requirement still needed? Consider removing if obsolete.",
                    related_req_ids=[req_id]
                ))
                issue_counter["INFO"] += 1

        return issues

    def _find_location(self, req_id: str, text: str, filename: str) -> Location:
        """Find the line number where a requirement ID appears.

        Args:
            req_id: Requirement ID to find
            text: Document text
            filename: Name of the file

        Returns:
            Location with file and line number
        """
        lines = text.split('\n')
        for i, line in enumerate(lines):
            if req_id in line:
                return Location(file=filename, line=i)

        # If not found, return line 0
        return Location(file=filename, line=0)
