"""Markdown parser for specification documents."""

import re
from typing import Dict, Set, List, Tuple
from markdown_it import MarkdownIt
from markdown_it.tree import SyntaxTreeNode

from ..models.parsed_document import (
    ParsedDocument,
    Section,
    DocType,
    ParsedSpecs
)
from .file_loader import SpecFiles


class MarkdownParser:
    """Parser for Markdown specification documents."""

    # Requirement ID patterns: [REQ-XXX], [NFR-XXX], [CON-XXX], [ASM-XXX], [T-XXX]
    REQ_ID_PATTERN = re.compile(r'\[(REQ|NFR|CON|ASM|T)-\d{3,}\]')

    def __init__(self) -> None:
        """Initialize Markdown parser."""
        self.md = MarkdownIt()

    def parse(self, markdown_text: str, doc_type: DocType) -> ParsedDocument:
        """Parse Markdown text into structured document.

        Args:
            markdown_text: Raw Markdown content
            doc_type: Type of document (requirement/design/tasks)

        Returns:
            ParsedDocument: Structured representation
        """
        # Parse Markdown to AST
        tokens = self.md.parse(markdown_text)

        # Extract sections
        sections = self._extract_sections(tokens, markdown_text)

        # Extract requirement IDs
        requirement_ids = self._extract_requirement_ids(markdown_text)

        return ParsedDocument(
            sections=sections,
            requirement_ids=requirement_ids,
            raw_text=markdown_text,
            doc_type=doc_type
        )

    def parse_specs(self, spec_files: SpecFiles) -> ParsedSpecs:
        """Parse all three specification files.

        Args:
            spec_files: Loaded specification files

        Returns:
            ParsedSpecs: All three parsed documents
        """
        requirement = self.parse(spec_files.requirement, DocType.REQUIREMENT)
        design = self.parse(spec_files.design, DocType.DESIGN)
        tasks = self.parse(spec_files.tasks, DocType.TASKS)

        return ParsedSpecs(
            requirement=requirement,
            design=design,
            tasks=tasks,
            project_name=spec_files.project_name
        )

    def _extract_sections(
        self,
        tokens: List,
        raw_text: str
    ) -> Dict[str, Section]:
        """Extract sections from Markdown tokens.

        Args:
            tokens: Markdown-it tokens
            raw_text: Original text for extracting content

        Returns:
            Dictionary of section title -> Section object
        """
        sections: Dict[str, Section] = {}
        current_section: Section | None = None
        section_stack: List[Section] = []  # For tracking hierarchy

        lines = raw_text.split('\n')
        current_heading: str | None = None
        current_level: int = 0
        content_lines: List[str] = []

        for i, token in enumerate(tokens):
            if token.type == 'heading_open':
                # Save previous section
                if current_heading and content_lines:
                    content = '\n'.join(content_lines).strip()
                    section = Section(
                        title=current_heading,
                        content=content,
                        subsections=[],
                        level=current_level
                    )
                    sections[current_heading] = section

                    # Handle hierarchy
                    while section_stack and section_stack[-1].level >= current_level:
                        section_stack.pop()
                    if section_stack:
                        section_stack[-1].subsections.append(section)
                    section_stack.append(section)

                    content_lines = []

                # Extract heading level
                current_level = int(token.tag[1])  # h1 -> 1, h2 -> 2, etc.

            elif token.type == 'inline' and current_level > 0:
                # This is the heading text
                current_heading = token.content

            elif token.type == 'heading_close':
                # Heading ended, start collecting content
                pass

            else:
                # Collect content (everything between headings)
                if current_heading and token.type in ['paragraph_open', 'bullet_list_open', 'code_block', 'fence']:
                    if token.map:
                        start_line, end_line = token.map
                        content_lines.extend(lines[start_line:end_line])

        # Save last section
        if current_heading and content_lines:
            content = '\n'.join(content_lines).strip()
            section = Section(
                title=current_heading,
                content=content,
                subsections=[],
                level=current_level
            )
            sections[current_heading] = section

        return sections

    def _extract_requirement_ids(self, text: str) -> Set[str]:
        """Extract all requirement IDs from text.

        Args:
            text: Markdown text

        Returns:
            Set of requirement IDs found in the document
        """
        matches = self.REQ_ID_PATTERN.findall(text)
        # matches are tuples like ('REQ', '001'), we need to reconstruct
        ids = set()
        for match in self.REQ_ID_PATTERN.finditer(text):
            ids.add(match.group(0))  # Full match like [REQ-001]
        return ids
