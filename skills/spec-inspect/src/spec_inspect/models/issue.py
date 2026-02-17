"""Issue data model for spec-inspect."""

from dataclasses import dataclass
from enum import Enum
from typing import Optional, List


class Severity(Enum):
    """Severity levels for issues."""
    CRITICAL = "Critical"  # Implementation blocker
    WARNING = "Warning"    # Needs review
    INFO = "Info"          # Improvement suggestion


@dataclass
class Location:
    """Location information for an issue."""
    file: str     # requirement.md | design.md | tasks.md
    line: int     # Line number (0-indexed)

    def __str__(self) -> str:
        return f"{self.file}:{self.line + 1}"


@dataclass
class Issue:
    """Represents a detected problem in specifications."""
    id: str                     # CRITICAL-001, WARNING-001, INFO-001
    severity: Severity          # Critical | Warning | Info
    title: str                  # Problem title
    description: str            # Detailed explanation
    location: Location          # File name and line number
    suggestion: Optional[str]   # Fix suggestion
    related_req_ids: List[str]  # Related requirement IDs

    def __post_init__(self) -> None:
        """Validate issue data."""
        if not self.id:
            raise ValueError("Issue ID cannot be empty")
        if not self.title:
            raise ValueError("Issue title cannot be empty")
        if self.related_req_ids is None:
            self.related_req_ids = []
