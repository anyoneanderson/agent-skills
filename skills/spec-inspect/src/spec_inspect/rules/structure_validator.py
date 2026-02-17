"""Structure validation rule for mandatory sections."""

from typing import List, Dict, Set

from ..core.check_engine import CheckRule
from ..models.issue import Issue, Severity, Location
from ..models.parsed_document import ParsedSpecs, DocType


class StructureValidator(CheckRule):
    """Validates that documents contain mandatory sections."""

    # Mandatory sections for each document type
    MANDATORY_SECTIONS: Dict[DocType, Set[str]] = {
        DocType.REQUIREMENT: {
            "概要",
            "機能要件",
            "非機能要件",
            "制約事項",
            "前提条件",
        },
        DocType.DESIGN: {
            "アーキテクチャ概要",
            "技術スタック",
            "データモデル",
        },
        DocType.TASKS: {
            "タスク一覧",
            "優先順位",
        },
    }

    def check(self, specs: ParsedSpecs) -> List[Issue]:
        """Check for mandatory sections in each document.

        Args:
            specs: Parsed specification documents

        Returns:
            List of issues for missing mandatory sections
        """
        issues: List[Issue] = []
        warning_counter = 1

        # Check requirement.md
        issues.extend(self._check_document_structure(
            specs.requirement,
            "requirement.md",
            warning_counter
        ))
        warning_counter += len(issues)

        # Check design.md
        issues.extend(self._check_document_structure(
            specs.design,
            "design.md",
            warning_counter
        ))
        warning_counter += len(issues)

        # Check tasks.md
        issues.extend(self._check_document_structure(
            specs.tasks,
            "tasks.md",
            warning_counter
        ))

        return issues

    def _check_document_structure(
        self,
        doc,
        filename: str,
        counter_start: int
    ) -> List[Issue]:
        """Check if a document has all mandatory sections.

        Args:
            doc: Parsed document
            filename: Document filename
            counter_start: Starting number for issue IDs

        Returns:
            List of issues for missing sections
        """
        issues: List[Issue] = []
        counter = counter_start

        mandatory = self.MANDATORY_SECTIONS.get(doc.doc_type, set())
        existing_sections = set(doc.sections.keys())

        # Check each mandatory section
        for section_title in mandatory:
            # Case-insensitive check
            found = any(
                section_title.lower() in existing.lower()
                for existing in existing_sections
            )

            if not found:
                issues.append(Issue(
                    id=f"WARNING-{counter:03d}",
                    severity=Severity.WARNING,
                    title=f"Missing mandatory section: {section_title}",
                    description=f"Document {filename} should contain a '{section_title}' section",
                    location=Location(file=filename, line=0),
                    suggestion=f"Add a '{section_title}' section to {filename}",
                    related_req_ids=[]
                ))
                counter += 1

        return issues
