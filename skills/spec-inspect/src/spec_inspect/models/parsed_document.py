"""Parsed document data models for spec-inspect."""

from dataclasses import dataclass, field
from typing import Dict, List, Set
from enum import Enum


class DocType(Enum):
    """Document type enumeration."""
    REQUIREMENT = "requirement"
    DESIGN = "design"
    TASKS = "tasks"


@dataclass
class Section:
    """Represents a section in a Markdown document."""
    title: str
    content: str
    subsections: List['Section'] = field(default_factory=list)
    level: int = 1  # Heading level (1-6)

    def __str__(self) -> str:
        return f"{'#' * self.level} {self.title}"


@dataclass
class ParsedDocument:
    """Structured representation of a parsed Markdown document."""
    sections: Dict[str, Section]  # Section title -> Section object
    requirement_ids: Set[str]     # [REQ-XXX], [NFR-XXX], etc.
    raw_text: str                 # Original Markdown text
    doc_type: DocType             # Document type

    def get_section(self, title: str) -> Section | None:
        """Get a section by title (case-insensitive)."""
        for section_title, section in self.sections.items():
            if section_title.lower() == title.lower():
                return section
        return None

    def has_requirement_id(self, req_id: str) -> bool:
        """Check if a requirement ID exists in this document."""
        return req_id in self.requirement_ids


@dataclass
class ParsedSpecs:
    """Container for all three parsed specification documents."""
    requirement: ParsedDocument
    design: ParsedDocument
    tasks: ParsedDocument
    project_name: str

    def __post_init__(self) -> None:
        """Validate document types."""
        if self.requirement.doc_type != DocType.REQUIREMENT:
            raise ValueError("Invalid requirement document type")
        if self.design.doc_type != DocType.DESIGN:
            raise ValueError("Invalid design document type")
        if self.tasks.doc_type != DocType.TASKS:
            raise ValueError("Invalid tasks document type")
