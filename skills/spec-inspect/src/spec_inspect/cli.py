"""Command-line interface for spec-inspect."""

import click
import sys
from pathlib import Path

from .core.file_loader import FileLoader
from .core.parser import MarkdownParser
from .core.check_engine import CheckEngine
from .core.report_generator import ReportGenerator
from .rules.requirement_id_validator import RequirementIDValidator
from .rules.structure_validator import StructureValidator


@click.command()
@click.argument('project_path', type=click.Path(exists=True))
@click.option(
    '--output',
    '-o',
    type=click.Path(),
    help='Output file for Markdown report'
)
@click.option(
    '--format',
    '-f',
    type=click.Choice(['console', 'markdown', 'both']),
    default='console',
    help='Output format (default: console)'
)
def main(project_path: str, output: str | None, format: str) -> None:
    """Inspect specification quality.

    PROJECT_PATH: Path to .specs/[project-name]/ directory

    Examples:
        spec-inspect .specs/my-project
        spec-inspect .specs/my-project -o report.md -f both
    """
    try:
        # 1. Load specification files
        click.echo(f"📂 Loading specifications from {project_path}...")
        loader = FileLoader()
        spec_files = loader.load_specs(project_path)
        click.echo(f"✅ Loaded project: {spec_files.project_name}\n")

        # 2. Parse Markdown documents
        click.echo("📝 Parsing Markdown documents...")
        parser = MarkdownParser()
        parsed_specs = parser.parse_specs(spec_files)
        click.echo("✅ Parsing complete\n")

        # 3. Initialize check rules
        click.echo("🔍 Running quality checks...")
        rules = [
            RequirementIDValidator(),
            StructureValidator(),
        ]
        engine = CheckEngine(rules)

        # 4. Run checks
        issues = engine.run_checks(parsed_specs)
        click.echo(f"✅ Checks complete: {len(issues)} issues found\n")

        # 5. Generate reports
        generator = ReportGenerator()

        # Console output
        if format in ['console', 'both']:
            console_output = generator.generate_console_output(issues)
            click.echo(console_output)

        # Markdown output
        if format in ['markdown', 'both']:
            markdown_report = generator.generate_markdown(
                issues,
                spec_files.project_name
            )

            if output:
                # Save to file
                output_path = Path(output)
                output_path.write_text(markdown_report, encoding='utf-8')
                click.echo(f"\n📄 Markdown report saved to: {output}")
            else:
                # Print to console
                click.echo("\n" + "="*80)
                click.echo(markdown_report)
                click.echo("="*80)

        # Exit with error code if critical issues found
        critical_count = sum(
            1 for issue in issues
            if issue.severity.value == "Critical"
        )
        if critical_count > 0:
            click.echo(f"\n❌ {critical_count} critical issue(s) found. Fix before implementation.")
            sys.exit(1)
        else:
            click.echo("\n✅ No critical issues found. Specifications look good!")
            sys.exit(0)

    except FileNotFoundError as e:
        click.echo(f"❌ Error: {e}", err=True)
        sys.exit(1)
    except ValueError as e:
        click.echo(f"❌ Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        click.echo(f"❌ Unexpected error: {e}", err=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
