#!/usr/bin/env python3
"""
NovelKit build script

作用：
- 将 NovelKit 元项目（`novelkit/` 目录）构建为可发布的包
- 目前只支持目标 AI = cursor，其它 AI 先标记为 TODO
- 目标平台参数目前只体现在输出目录结构上（如 dist/cursor-linux 或 dist/cursor-win）

输出目录结构（相对于仓库根目录 `./`）：

dist/
  cursor-linux/                 # 或 cursor-win / 未来可能是 claude-linux 等
    .novelkit/                  # 元空间模板（发布包内的初始结构）
      memory/
        config.json             # 初始状态机（从 ./memory/config.json 复制）
      templates/                # 从 ./templates/ 复制
      scripts/                  # 从 ./scripts/ 复制
      writers/                  # 空目录（运行时由命令生成）
      chapters/                 # 空目录（运行时由命令生成）
    .cursor/
      commands/
        novel.writer.new.md
        novel.writer.list.md
        ...

使用示例：
    python -m novelkit.build cursor linux
    python ./build.py cursor win
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Callable


def load_build_config() -> tuple[set[str], set[str]]:
    """从 build-config.json 加载构建配置"""
    config_path = Path(__file__).parent / "build-config.json"
    if not config_path.exists():
        # 默认配置（向后兼容）
        return {"cursor"}, {"linux", "win"}
    
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    
    supported_ais = set(config.get("supported_ais", ["cursor"]))
    supported_platforms = set(config.get("supported_platforms", ["linux", "win"]))
    
    return supported_ais, supported_platforms


SUPPORTED_AIS, SUPPORTED_PLATFORMS = load_build_config()


# AI 环境配置
# 定义每个 AI 环境的格式、目录结构、参数格式等
# 与 spec-kit 保持一致，支持所有相同的 AI 环境
AI_ENV_CONFIG: dict[str, dict] = {
    "claude": {
        "folder": ".claude/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "gemini": {
        "folder": ".gemini/commands",
        "format": "toml",
        "arg_format": "{{args}}",
        "name_converter": "to_novel_command_name",
    },
    "copilot": {
        "folder": ".github/agents",
        "format": "agent.md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "cursor-agent": {
        "folder": ".cursor/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "cursor": {
        # cursor 是 cursor-agent 的别名，使用相同的配置
        "folder": ".cursor/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "qwen": {
        "folder": ".qwen/commands",
        "format": "toml",
        "arg_format": "{{args}}",
        "name_converter": "to_novel_command_name",
    },
    "opencode": {
        "folder": ".opencode/command",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "windsurf": {
        "folder": ".windsurf/workflows",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "codex": {
        "folder": ".codex/prompts",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "kilocode": {
        "folder": ".kilocode/workflows",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "auggie": {
        "folder": ".augment/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "roo": {
        "folder": ".roo/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "codebuddy": {
        "folder": ".codebuddy/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "qoder": {
        "folder": ".qoder/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "amp": {
        "folder": ".agents/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "shai": {
        "folder": ".shai/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "q": {
        "folder": ".amazonq/prompts",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
    "bob": {
        "folder": ".bob/commands",
        "format": "md",
        "arg_format": "$ARGUMENTS",
        "name_converter": "to_novel_command_name",
    },
}


def find_repo_root() -> Path:
    """
    仓库根目录 = build.py 所在的目录
    """
    here = Path(__file__).resolve()
    repo_root = here.parent
    # Check for a key directory to validate root
    if not (repo_root / "commands").is_dir():
        print(f"Error: could not find 'commands' directory in {repo_root}", file=sys.stderr)
        sys.exit(1)
    return repo_root


def copy_tree(src: Path, dst: Path) -> None:
    """递归复制目录（允许目标已存在）。"""
    if not src.exists():
        return
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            copy_tree(item, target)
        else:
            shutil.copy2(item, target)


def build_for_ai(repo_root: Path, ai: str, platform: str) -> Path:
    """
    构建指定 AI 环境的发布包。

    :param repo_root: 仓库根目录（与 ./ 同级）
    :param ai: AI 环境名称
    :param platform: 平台标识（linux / win）
    :return: 构建输出目录路径
    """
    config = AI_ENV_CONFIG.get(ai)
    if not config:
        raise ValueError(f"Unsupported AI environment: {ai}")

    # 目录命名规则：dist/{ai}-{platform}
    dist_root = repo_root / "dist" / f"{ai}-{platform}"

    # 1. 准备目标目录
    meta_target = dist_root / ".novelkit"
    commands_folder = config["folder"]
    commands_target = dist_root / commands_folder

    # 清理旧产物（如果存在）
    if dist_root.exists():
        shutil.rmtree(dist_root)

    meta_target.mkdir(parents=True, exist_ok=True)
    commands_target.mkdir(parents=True, exist_ok=True)

    # 2. 复制 .novelkit 内容
    # 2.1 memory/config.json（初始状态机模板）
    src_config = repo_root / "memory" / "config.json"
    memory_target = meta_target / "memory"
    memory_target.mkdir(parents=True, exist_ok=True)
    if src_config.is_file():
        shutil.copy2(src_config, memory_target / "config.json")
    else:
        print(
            "Warning: ./memory/config.json not found, "
            "memory/config.json will be missing in package.",
            file=sys.stderr,
        )

    # 2.2 templates/
    src_templates = repo_root / "templates"
    copy_tree(src_templates, meta_target / "templates")

    # 2.3 scripts/（只复制指定平台的脚本）
    scripts_target = meta_target / "scripts"
    scripts_target.mkdir(parents=True, exist_ok=True)
    
    if platform == "linux":
        # Linux 平台：只复制 bash 脚本
        src_bash = repo_root / "scripts" / "bash"
        if src_bash.is_dir():
            copy_tree(src_bash, scripts_target / "bash")
        else:
            print(
                f"Warning: ./scripts/bash not found for platform '{platform}'.",
                file=sys.stderr,
            )
    elif platform == "win":
        # Windows 平台：只复制 PowerShell 脚本
        src_powershell = repo_root / "scripts" / "powershell"
        if src_powershell.is_dir():
            copy_tree(src_powershell, scripts_target / "powershell")
        else:
            print(
                f"Warning: ./scripts/powershell not found for platform '{platform}'.",
                file=sys.stderr,
            )
    else:
        print(
            f"Warning: Unknown platform '{platform}', skipping scripts copy.",
            file=sys.stderr,
        )

    # 注意：writers/ 和 chapters/ 目录不需要在构建时创建
    # 它们会在运行时由脚本自动创建

    # 3. 转换命令文件到目标 AI 环境格式
    src_commands = repo_root / "commands"
    if not src_commands.is_dir():
        print(
            "Warning: ./commands not found, no commands will be packaged.",
            file=sys.stderr,
        )
    else:
        for cmd_file in src_commands.glob("*.md"):
            convert_command_file(cmd_file, ai, platform, commands_target)

    # 4. AI 特定的额外文件（如果需要）
    # 例如：Gemini 和 Qwen 可能需要额外的说明文件
    if ai == "gemini":
        gemini_readme = repo_root / "agent_templates" / "gemini" / "GEMINI.md"
        if gemini_readme.exists():
            shutil.copy2(gemini_readme, dist_root / "GEMINI.md")
    elif ai == "qwen":
        qwen_readme = repo_root / "agent_templates" / "qwen" / "QWEN.md"
        if qwen_readme.exists():
            shutil.copy2(qwen_readme, dist_root / "QWEN.md")
    elif ai == "copilot":
        # GitHub Copilot 可能需要 VS Code 设置
        vscode_settings = repo_root / "templates" / "vscode-settings.json"
        if vscode_settings.exists():
            vscode_dir = dist_root / ".vscode"
            vscode_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(vscode_settings, vscode_dir / "settings.json")

    return dist_root


# 保持向后兼容
def build_for_cursor(repo_root: Path, platform: str) -> Path:
    """向后兼容的 cursor 构建函数"""
    return build_for_ai(repo_root, "cursor", platform)


def to_novel_command_name(src_name: str, extension: str = ".md") -> str:
    """
    将 ./commands 下的文件名转换为统一的命令名格式。

    规则：
    - 去掉扩展名，按 `-` 分割
    - 如果前缀是 `novel-`，先去掉 `novel-`
    - 最终格式：novel.<part1>.<part2>... + 扩展名

    例：
    - writer-new.md           -> novel.writer.new.md
    - writer-list.md          -> novel.writer.list.md
    - constitution-create.md  -> novel.constitution.create.md
    - chapter-plan.md         -> novel.chapter.plan.md
    - novel-setup.md          -> novel.setup.md
    """
    base = src_name
    if base.lower().endswith(".md"):
        base = base[:-3]

    # 去掉前缀 novel-
    lower = base.lower()
    if lower.startswith("novel-"):
        base = base[len("novel-") :]

    parts = base.split("-")
    parts = [p for p in parts if p]  # 去掉空

    if not parts:
        # 极端情况：fallback 原名
        return src_name

    new_base = "novel." + ".".join(parts)
    return new_base + extension


def parse_frontmatter(content: str) -> tuple[dict, str]:
    """
    解析 Markdown 文件的 YAML frontmatter。

    Returns:
        (frontmatter_dict, body_content)
    """
    frontmatter = {}
    body = content

    # 检查是否有 frontmatter
    if not content.startswith("---"):
        return frontmatter, body

    # 找到第二个 ---
    parts = content.split("---", 2)
    if len(parts) < 3:
        return frontmatter, body

    frontmatter_text = parts[1].strip()
    body = parts[2]

    # 解析 YAML frontmatter
    in_scripts = False
    scripts = {}
    
    for line in frontmatter_text.split("\n"):
        line_stripped = line.strip()
        if not line_stripped:
            continue

        # 检查是否是 scripts: 开始
        if line_stripped == "scripts:":
            in_scripts = True
            continue

        # 检查是否是其他顶级键（结束 scripts）
        # 顶级键不以空格开头
        if in_scripts and ":" in line_stripped and not line.startswith(" ") and not line.startswith("\t"):
            in_scripts = False

        if in_scripts:
            # 解析 scripts 下的子键（sh:, ps:）
            # 这些行应该以空格或制表符开头
            if (line.startswith(" ") or line.startswith("\t")) and ":" in line_stripped:
                key, value = line_stripped.split(":", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                scripts[key] = value
        else:
            # 解析其他顶级键值对
            if ":" in line_stripped:
                key, value = line_stripped.split(":", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                frontmatter[key] = value

    if scripts:
        frontmatter["scripts"] = scripts

    return frontmatter, body


def extract_scripts_from_content(content: str) -> dict[str, str]:
    """
    从完整内容中提取 scripts 配置（备用方法）。

    Returns:
        {"sh": "...", "ps": "..."}
    """
    scripts = {}
    
    # 使用正则表达式提取 scripts 部分
    scripts_match = re.search(
        r"^scripts:\s*\n((?:\s+[a-z]+:.*\n?)+)",
        content,
        re.MULTILINE,
    )
    if scripts_match:
        scripts_text = scripts_match.group(1)
        for line in scripts_text.split("\n"):
            line = line.strip()
            if not line:
                continue
            if ":" in line:
                key, value = line.split(":", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                scripts[key] = value

    return scripts


def rewrite_paths(content: str) -> str:
    """
    重写路径：将相对路径转换为 .novelkit/ 下的路径。
    
    目前 novel-kit 使用 .novelkit/ 作为根目录，不需要重写。
    但如果将来需要，可以在这里添加逻辑。
    """
    # 如果需要重写，可以这样做：
    # content = re.sub(r'\bmemory/', '.novelkit/memory/', content)
    # content = re.sub(r'\bscripts/', '.novelkit/scripts/', content)
    # content = re.sub(r'\btemplates/', '.novelkit/templates/', content)
    return content


def convert_command_file(
    cmd_file: Path,
    ai: str,
    platform: str,
    output_dir: Path,
) -> None:
    """
    将命令文件转换为指定 AI 环境的格式。

    :param cmd_file: 源命令文件路径
    :param ai: AI 环境名称
    :param platform: 平台（linux/win）
    :param output_dir: 输出目录
    """
    config = AI_ENV_CONFIG.get(ai)
    if not config:
        print(f"Warning: No config for AI '{ai}', skipping {cmd_file.name}", file=sys.stderr)
        return

    # 读取源文件
    content = cmd_file.read_text(encoding="utf-8")

    # 提取 frontmatter
    frontmatter, body = parse_frontmatter(content)
    description = frontmatter.get("description", "")

    # 提取 scripts（优先从 frontmatter，否则从完整内容）
    scripts = frontmatter.get("scripts", {})
    if not scripts:
        scripts = extract_scripts_from_content(content)
    
    # 根据平台选择脚本
    script_key = "sh" if platform == "linux" else "ps"
    script_command = scripts.get(script_key, "")
    
    if not script_command:
        print(
            f"Warning: No {script_key} script found in {cmd_file.name}",
            file=sys.stderr,
        )
        script_command = f"(Missing {script_key} script)"

    # 替换占位符
    body = body.replace("{SCRIPT}", script_command)
    # 替换参数格式：$ARGUMENTS -> 对应 AI 环境的格式
    body = body.replace("$ARGUMENTS", config["arg_format"])
    # 也支持 {ARGS} 占位符（如果源文件中使用了）
    body = body.replace("{ARGS}", config["arg_format"])
    
    # 路径重写
    body = rewrite_paths(body)

    # 移除 frontmatter 中的 scripts 部分（在 body 中）
    # 这里简化处理，直接使用 body（已经去掉了 frontmatter）

    # 生成文件名
    base_name = cmd_file.stem
    new_name = to_novel_command_name(base_name, extension="")
    
    # 根据格式生成文件
    format_type = config["format"]
    output_file = output_dir / f"{new_name}.{format_type}"

    if format_type == "toml":
        # 转换为 TOML 格式
        # 转义反斜杠和引号
        body_escaped = body.replace("\\", "\\\\").replace('"', '\\"')
        toml_content = f'description = "{description}"\n\nprompt = """\n{body}\n"""'
        output_file.write_text(toml_content, encoding="utf-8")
    elif format_type == "agent.md":
        # GitHub Copilot agent.md 格式
        # 保持 Markdown 格式，但可能需要特殊处理
        output_file.write_text(body, encoding="utf-8")
    else:
        # Markdown 格式（默认）
        output_file.write_text(body, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build NovelKit distribution packages.")
    parser.add_argument(
        "ai",
        help=f"目标 AI（支持: {', '.join(sorted(SUPPORTED_AIS))}, 或 'all' 构建所有）",
        nargs="?",
        default="cursor",
    )
    parser.add_argument(
        "platform",
        help=f"目标平台（{', '.join(sorted(SUPPORTED_PLATFORMS))}），使用 'all' 时忽略此参数",
        nargs="?",
        default="linux",
    )
    return parser.parse_args(argv)


def build_all(repo_root: Path) -> list[Path]:
    """
    构建所有支持的 AI 环境和平台组合。
    
    Returns:
        构建输出目录列表
    """
    output_dirs = []
    for ai in SUPPORTED_AIS:
        if ai not in AI_ENV_CONFIG:
            print(
                f"Warning: AI '{ai}' is in config but not implemented in AI_ENV_CONFIG. "
                f"Supported: {list(AI_ENV_CONFIG.keys())}",
                file=sys.stderr,
            )
            continue
        
        for platform in SUPPORTED_PLATFORMS:
            try:
                out_dir = build_for_ai(repo_root, ai, platform)
                output_dirs.append(out_dir)
                print(f"✓ Built NovelKit package for ai='{ai}', platform='{platform}' at: {out_dir}")
            except Exception as e:
                print(
                    f"✗ Failed to build ai='{ai}', platform='{platform}': {e}",
                    file=sys.stderr,
                )
                continue
    
    return output_dirs


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    args = parse_args(argv)
    ai = args.ai.lower()
    platform = args.platform.lower()

    # 特殊处理：如果 ai 为 "all"，构建所有支持的 AI 环境
    if ai == "all":
        repo_root = find_repo_root()
        output_dirs = build_all(repo_root)
        if not output_dirs:
            print("Error: No packages were built.", file=sys.stderr)
            return 1
        return 0

    if ai not in SUPPORTED_AIS:
        print(f"TODO: AI '{ai}' not supported yet. Supported: {sorted(SUPPORTED_AIS)}", file=sys.stderr)
        print(f"Use 'all' to build all supported AI environments.", file=sys.stderr)
        return 1

    if platform not in SUPPORTED_PLATFORMS:
        print(
            f"Warning: platform '{platform}' is not in {sorted(SUPPORTED_PLATFORMS)}. "
            f"Using it as directory name anyway.",
            file=sys.stderr,
        )

    repo_root = find_repo_root()

    if ai not in AI_ENV_CONFIG:
        print(
            f"Error: AI '{ai}' is not in AI_ENV_CONFIG. "
            f"Supported: {list(AI_ENV_CONFIG.keys())}",
            file=sys.stderr,
        )
        return 1

    try:
        out_dir = build_for_ai(repo_root, ai, platform)
        config = AI_ENV_CONFIG[ai]
        print(f"✓ Built NovelKit package for ai='{ai}', platform='{platform}' at: {out_dir}")
        print(f"  meta-space   : {out_dir / '.novelkit'}")
        print(f"  commands     : {out_dir / config['folder']}")
        return 0
    except Exception as e:
        print(f"Error: Failed to build package: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
