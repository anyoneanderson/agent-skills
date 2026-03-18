#!/usr/bin/env python3
"""Convert Claude Code MCP settings into Codex CLI MCP configuration."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def expand(path: str) -> Path:
    return Path(path).expanduser().resolve()


def toml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def toml_quote(value: str) -> str:
    return f'"{toml_escape(value)}"'


@dataclass
class Server:
    name: str
    type: str
    command: Optional[str]
    args: List[str]
    env: Dict[str, str]
    url: Optional[str]


@dataclass
class ConvertedServer:
    server: Server
    command: Optional[str]
    args: List[str]
    env: Dict[str, str]


def load_claude_servers(source_path: Path) -> Dict[str, Server]:
    data = json.loads(source_path.read_text())
    raw_servers = data.get("mcpServers", {})
    if not isinstance(raw_servers, dict):
        raise ValueError("Expected top-level mcpServers object in Claude config")

    servers: Dict[str, Server] = {}
    for name, payload in raw_servers.items():
        if not isinstance(payload, dict):
            continue
        server_type = payload.get("type", "stdio")
        command = payload.get("command")
        args = payload.get("args") or []
        env = payload.get("env") or {}
        url = payload.get("url")

        if not isinstance(args, list):
            raise ValueError(f"Server {name!r} has non-list args")
        if not isinstance(env, dict):
            raise ValueError(f"Server {name!r} has non-object env")

        servers[name] = Server(
            name=name,
            type=server_type,
            command=command,
            args=[str(arg) for arg in args],
            env={str(k): str(v) for k, v in env.items()},
            url=str(url) if url is not None else None,
        )
    return servers


def selected_servers(servers: Dict[str, Server], names: Iterable[str]) -> List[Server]:
    selected = list(names)
    if not selected:
        return list(servers.values())
    missing = [name for name in selected if name not in servers]
    if missing:
        raise ValueError(f"Unknown server names: {', '.join(missing)}")
    return [servers[name] for name in selected]


def convert_server(server: Server) -> ConvertedServer:
    if server.type == "stdio":
        if not server.command:
            raise ValueError(f"Server {server.name!r} is stdio but has no command")
        return ConvertedServer(
            server=server,
            command=server.command,
            args=server.args,
            env=server.env,
        )

    if server.type in {"http", "sse", "streamable_http"}:
        if not server.url:
            raise ValueError(f"Server {server.name!r} is {server.type} but has no url")
        return ConvertedServer(
            server=server,
            command=None,
            args=[],
            env=server.env,
        )

    raise ValueError(f"Unsupported MCP server type for {server.name!r}: {server.type}")


def codex_list_json() -> Dict[str, dict]:
    result = subprocess.run(
        ["codex", "mcp", "list", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout or "[]")
    if isinstance(data, list):
        return {item["name"]: item for item in data if isinstance(item, dict) and "name" in item}
    if isinstance(data, dict):
        return {item["name"]: item for item in data.get("servers", []) if isinstance(item, dict)}
    return {}


def apply_server(converted: ConvertedServer, overwrite: bool) -> str:
    server = converted.server
    current = codex_list_json()
    if server.name in current:
        if not overwrite:
            return f"skip {server.name}: already exists"
        subprocess.run(["codex", "mcp", "remove", server.name], check=True)

    if server.type == "stdio":
        cmd = ["codex", "mcp", "add", server.name]
        for key, value in sorted(converted.env.items()):
            cmd.extend(["--env", f"{key}={value}"])
        cmd.append("--")
        cmd.append(converted.command or "")
        cmd.extend(converted.args)
        subprocess.run(cmd, check=True)
        return f"added {server.name}"

    if server.type in {"http", "sse", "streamable_http"}:
        cmd = ["codex", "mcp", "add", server.name, "--url", server.url or ""]
        subprocess.run(cmd, check=True)
        return f"added {server.name}"

    raise ValueError(f"Unsupported MCP server type for {server.name!r}: {server.type}")


def toml_block(converted: ConvertedServer) -> str:
    server = converted.server
    lines = [f"[mcp_servers.{server.name}]"]
    if server.type == "stdio":
        lines.append(f"command = {toml_quote(converted.command or '')}")
        args = ", ".join(toml_quote(arg) for arg in converted.args)
        lines.append(f"args = [{args}]")
        if converted.env:
            lines.append("")
            lines.append(f"[mcp_servers.{server.name}.env]")
            for key, value in sorted(converted.env.items()):
                lines.append(f"{key} = {toml_quote(value)}")
    elif server.type in {"http", "sse", "streamable_http"}:
        lines.append(f"url = {toml_quote(server.url or '')}")
        if converted.env:
            lines.append("")
            lines.append(f"[mcp_servers.{server.name}.env]")
            for key, value in sorted(converted.env.items()):
                lines.append(f"{key} = {toml_quote(value)}")
    else:
        raise ValueError(f"Unsupported MCP server type for {server.name!r}: {server.type}")
    return "\n".join(lines)


def describe_server(converted: ConvertedServer) -> List[str]:
    server = converted.server
    lines = [f"- {server.name}: type={server.type}"]
    if server.type == "stdio":
        command_bits = [converted.command or ""] + converted.args
        lines.append(f"  target: {' '.join(shlex.quote(bit) for bit in command_bits)}")
    else:
        lines.append(f"  target: {server.url}")
    if converted.env:
        lines.append(f"  env: {', '.join(sorted(converted.env))}")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert Claude Code MCP settings into Codex CLI MCP configuration."
    )
    parser.add_argument(
        "--source",
        default="~/.claude.json",
        help="Path to the Claude config JSON file.",
    )
    parser.add_argument(
        "--mode",
        choices=["dry-run", "apply", "export-toml"],
        default="dry-run",
        help="What to do with the converted servers.",
    )
    parser.add_argument(
        "--server",
        action="append",
        default=[],
        help="Server name to include. Repeat to select multiple servers.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing Codex MCP entries with the same name.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    source_path = expand(args.source)

    if not source_path.exists():
        parser.error(f"Claude config not found: {source_path}")

    servers = load_claude_servers(source_path)
    chosen = selected_servers(servers, args.server)
    converted = [convert_server(server) for server in chosen]

    if args.mode == "dry-run":
        print(f"Source: {source_path}")
        print(f"Servers: {len(converted)}")
        for item in converted:
            print("\n".join(describe_server(item)))
        return 0

    if args.mode == "export-toml":
        print(
            "\n\n".join(toml_block(item) for item in converted),
            end="\n" if converted else "",
        )
        return 0

    if args.mode == "apply":
        for item in converted:
            print(apply_server(item, overwrite=args.overwrite))
        return 0

    parser.error(f"Unsupported mode: {args.mode}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
