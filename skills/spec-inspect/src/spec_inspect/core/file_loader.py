"""File loader for specification documents."""

from dataclasses import dataclass
from pathlib import Path
from typing import Tuple


@dataclass
class SpecFiles:
    """Container for the three specification files."""
    requirement: str  # requirement.md content
    design: str       # design.md content
    tasks: str        # tasks.md content
    project_name: str


class FileLoader:
    """Loads specification files from a project directory."""

    REQUIRED_FILES = ["requirement.md", "design.md", "tasks.md"]

    def load_specs(self, project_path: str) -> SpecFiles:
        """Load all three specification files.

        Args:
            project_path: Path to .specs/[project-name]/ directory

        Returns:
            SpecFiles: Loaded specification documents

        Raises:
            FileNotFoundError: If required files are missing
            ValueError: If project_path is invalid
        """
        path = Path(project_path)

        # Sanitize path (prevent directory traversal)
        try:
            path = path.resolve(strict=True)
        except (OSError, RuntimeError) as e:
            raise ValueError(f"Invalid project path: {project_path}") from e

        if not path.is_dir():
            raise ValueError(f"Project path is not a directory: {project_path}")

        # Extract project name
        project_name = path.name

        # Load each required file
        requirement_path = path / "requirement.md"
        design_path = path / "design.md"
        tasks_path = path / "tasks.md"

        # Check file existence
        missing_files = []
        for file_name, file_path in [
            ("requirement.md", requirement_path),
            ("design.md", design_path),
            ("tasks.md", tasks_path),
        ]:
            if not file_path.exists():
                missing_files.append(file_name)

        if missing_files:
            raise FileNotFoundError(
                f"Missing required files in {project_path}: {', '.join(missing_files)}"
            )

        # Read file contents
        try:
            requirement_content = requirement_path.read_text(encoding="utf-8")
            design_content = design_path.read_text(encoding="utf-8")
            tasks_content = tasks_path.read_text(encoding="utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"File encoding error: {e}") from e
        except OSError as e:
            raise IOError(f"Error reading files: {e}") from e

        return SpecFiles(
            requirement=requirement_content,
            design=design_content,
            tasks=tasks_content,
            project_name=project_name
        )
