"""Inspection result data model for workflow integration."""

from dataclasses import dataclass, asdict
from datetime import datetime
from typing import List
import json

from .issue import Issue


@dataclass
class InspectionResult:
    """Summary of inspection results for workflow coordination."""
    project_path: str
    project_name: str
    critical_count: int
    warning_count: int
    info_count: int
    issues: List[Issue]
    report_path: str  # Path to inspection-report.md
    timestamp: datetime

    @property
    def total_issues(self) -> int:
        """Total number of issues detected."""
        return self.critical_count + self.warning_count + self.info_count

    @property
    def has_critical_issues(self) -> bool:
        """Check if there are any critical issues."""
        return self.critical_count > 0

    @property
    def has_warnings(self) -> bool:
        """Check if there are any warnings or info issues."""
        return self.warning_count > 0 or self.info_count > 0

    def to_json(self) -> str:
        """Serialize to JSON for inter-skill communication."""
        data = {
            "project_path": self.project_path,
            "project_name": self.project_name,
            "critical_count": self.critical_count,
            "warning_count": self.warning_count,
            "info_count": self.info_count,
            "report_path": self.report_path,
            "timestamp": self.timestamp.isoformat(),
            "summary": {
                "total_issues": self.total_issues,
                "severity_breakdown": {
                    "Critical": self.critical_count,
                    "Warning": self.warning_count,
                    "Info": self.info_count
                }
            }
        }
        return json.dumps(data, indent=2)

    @classmethod
    def from_json(cls, json_str: str) -> 'InspectionResult':
        """Deserialize from JSON."""
        data = json.loads(json_str)
        return cls(
            project_path=data["project_path"],
            project_name=data["project_name"],
            critical_count=data["critical_count"],
            warning_count=data["warning_count"],
            info_count=data["info_count"],
            issues=[],  # Issues not serialized in JSON
            report_path=data["report_path"],
            timestamp=datetime.fromisoformat(data["timestamp"])
        )
