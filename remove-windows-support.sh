#!/usr/bin/env bash
#
# remove-windows-support.sh
#
# Automated script to remove Windows support from this Zed/Xenomorphic fork.
#
# USAGE:
#   1. Review this script before running it
#   2. Make sure you have a clean git working tree (so you can git checkout if needed)
#   3. Run: bash remove-windows-support.sh
#   4. Review changes with: git diff --stat && git diff
#   5. Run cargo check on macOS (and ideally Linux too)
#   6. Handle the remaining manual items listed at the end
#
# SAFETY: This script only modifies files in crates/ and .github/
#          It does NOT touch Cargo.lock (cargo will regenerate it)
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

DRY_RUN="${DRY_RUN:-false}"  # Set DRY_RUN=true to see what would change without writing

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ============================================================
# PHASE 1: Delete entire Windows-only crates and directories
# ============================================================
log "=== Phase 1: Deleting Windows-only crates and directories ==="

ITEMS_TO_DELETE=(
    "crates/gpui_windows"
    "crates/windows_resources"
    "crates/etw_tracing"
    "crates/explorer_command_injector"
    "crates/gpui/resources/windows"
    "crates/xenomorphic/resources/windows"
    "crates/platform_title_bar/src/platforms/platform_windows.rs"
    "crates/remote_server/src/windows.rs"
    "crates/xenomorphic/src/xenomorphic_app/windows_only_instance.rs"
    "script/bundle-windows.ps1"
)

for item in "${ITEMS_TO_DELETE[@]}"; do
    if [ -e "$item" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo "  Would delete: $item"
        else
            rm -rf "$item"
            echo "  Deleted: $item"
        fi
    else
        warn "  Not found (already gone?): $item"
    fi
done

# ============================================================
# PHASE 2: Workspace Cargo.toml cleanup
# ============================================================
log "=== Phase 2: Workspace Cargo.toml cleanup ==="

python3 << 'PYEOF'
import re, sys

dry_run = sys.argv[1] == "true" if len(sys.argv) > 1 else False

with open('Cargo.toml', 'r') as f:
    content = f.read()
original = content

# Remove workspace member entries for Windows crates
for crate in ['crates/gpui_windows', 'crates/windows_resources', 'crates/etw_tracing', 'crates/explorer_command_injector']:
    content = re.sub(r'^\s*"' + re.escape(crate) + r'",?\s*\n', '', content, flags=re.MULTILINE)

# Remove workspace dependency lines for windows-specific packages
for dep in ['gpui_windows', 'windows_resources', 'etw_tracing', 'explorer_command_injector', 'windows-capture']:
    content = re.sub(r'^' + re.escape(dep) + r'\s*=\s*\{[^}]*\}\s*\n', '', content, flags=re.MULTILINE)

# Remove [workspace.dependencies.windows] section
content = re.sub(
    r'^\[workspace\.dependencies\.windows\]\s*\n(?:[^\[]*\n)*',
    '',
    content,
    flags=re.MULTILINE
)

# Remove windows-core dependency line
content = re.sub(r'^windows-core\s*=\s*"[^"]*"\s*\n', '', content, flags=re.MULTILINE)

# Remove standalone windows = { ... } in workspace deps (already handled by section removal, but just in case)
content = re.sub(r'^windows\s*=\s*\{[^}]*\}\s*\n', '', content, flags=re.MULTILINE)

# Clean up excessive blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

if content != original:
    if dry_run:
        print("  Would modify Cargo.toml (workspace)")
    else:
        with open('Cargo.toml', 'w') as f:
            f.write(content)
        print("  Modified Cargo.toml (workspace)")
else:
    print("  No changes needed in Cargo.toml (workspace)")
PYEOF

# ============================================================
# PHASE 3: Per-crate Cargo.toml cleanup
# ============================================================
log "=== Phase 3: Per-crate Cargo.toml cleanup ==="

python3 << 'PYEOF'
import re, glob

toml_files = sorted(glob.glob('crates/**/Cargo.toml', recursive=True))
changed_files = []

for toml_file in toml_files:
    with open(toml_file, 'r') as f:
        content = f.read()
    original = content

    # 1. Remove [target.'cfg(target_os = "windows")'.XXX] sections entirely
    #    These sections run until the next [ at column 0
    content = re.sub(
        r"""^\[target\.'cfg\(target_os = "windows"\)'\.\w+\]\s*\n(?:[^\[\n][^\n]*\n)*""",
        '',
        content,
        flags=re.MULTILINE
    )

    # 2. Simplify cfg(any(..., target_os = "windows", ...)) in target specifications
    #    Process each [target.'cfg(...)'.XXX] header
    def simplify_target_cfg(match):
        header = match.group(0)
        # Remove ', target_os = "windows"' from any() clauses
        header = re.sub(r',\s*target_os = "windows"', '', header)
        header = re.sub(r'target_os = "windows",\s*', '', header)
        # Simplify any() with single item
        header = re.sub(r'any\(\s*target_os = "([^"]+)"\s*\)', r'target_os = "\1"', header)
        return header

    content = re.sub(r'\[target\.\'[^\']+\'.*?\]', simplify_target_cfg, content)

    # 3. Simplify specific common patterns:
    #    any(target_os = "windows", target_os = "macos") -> target_os = "macos"
    #    any(target_os = "macos", target_os = "windows") -> target_os = "macos"
    content = re.sub(
        r'any\(\s*target_os = "windows",\s*target_os = "macos"\s*\)',
        'target_os = "macos"',
        content
    )
    content = re.sub(
        r'any\(\s*target_os = "macos",\s*target_os = "windows"\s*\)',
        'target_os = "macos"',
        content
    )

    #    not(any(target_os = "windows", target_os = "macos")) -> not(target_os = "macos")
    content = re.sub(
        r'not\(any\(\s*target_os = "windows",\s*target_os = "macos"\s*\)\)',
        'not(target_os = "macos")',
        content
    )
    content = re.sub(
        r'not\(any\(\s*target_os = "macos",\s*target_os = "windows"\s*\)\)',
        'not(target_os = "macos")',
        content
    )

    #    not(any(target_os = "linux", target_os = "freebsd", target_os = "windows")) -> not(any(target_os = "linux", target_os = "freebsd"))
    content = re.sub(
        r'not\(any\(\s*target_os = "linux",\s*target_os = "freebsd",\s*target_os = "windows"\s*\)\)',
        'not(any(target_os = "linux", target_os = "freebsd"))',
        content
    )

    # 4. Remove gpui_windows from feature lists
    content = re.sub(r'"gpui_windows/[^"]*",\s*', '', content)
    content = re.sub(r',\s*"gpui_windows/[^"]*"', '', content)

    # 5. Remove windows_resources from build-dependencies (unconditional lines)
    content = re.sub(r'^windows_resources\s*=\s*\{[^}]*\}\s*\n', '', content, flags=re.MULTILINE)

    # 6. Remove "windows-manifest" from feature lists
    content = re.sub(r'"windows-manifest",\s*', '', content)
    content = re.sub(r',\s*"windows-manifest"', '', content)

    # 7. Remove windows-manifest feature definition line
    content = re.sub(r'^windows-manifest\s*=\s*\[[^\]]*\]\s*\n', '', content, flags=re.MULTILINE)

    # 8. Remove gpui_windows/etw_tracing from dependencies (unconditional)
    for dep in ['gpui_windows', 'etw_tracing']:
        content = re.sub(r'^' + dep + r'\.?\w*\s*=\s*\{[^}]*\}\s*\n', '', content, flags=re.MULTILINE)

    # 9. Remove gpui = { workspace = true, features = ["windows-manifest"] }
    content = re.sub(r',\s*features\s*=\s*\["windows-manifest"\]', '', content)

    # 10. Remove windows = { ... } dependency lines (inside cfg(windows) sections, already removed)
    #     But also check for unconditional ones
    content = re.sub(r'^windows\s*=\s*\{[^}]*\}\s*\n', '', content, flags=re.MULTILINE)

    # Clean up blank lines
    content = re.sub(r'\n{3,}', '\n\n', content)

    if content != original:
        with open(toml_file, 'w') as f:
            f.write(content)
        changed_files.append(toml_file)
        print(f'  Modified {toml_file}')

print(f'\n  Modified {len(changed_files)} Cargo.toml files')
PYEOF

# ============================================================
# PHASE 4: Rust source file cleanup (the big one - uses Python)
# ============================================================
log "=== Phase 4: Rust source file cleanup ==="

# We need a Python script that can properly handle Rust cfg blocks.
# The key challenge is removing the code block after a #[cfg(target_os = "windows")]
# while handling nested braces correctly.

python3 << 'PYEOF'
import re, glob, os

EXCLUDED_CRATES = {'gpui_windows', 'windows_resources', 'etw_tracing', 'explorer_command_injector'}
EXCLUDED_DIRS = {'target'}

def is_excluded(filepath):
    for d in EXCLUDED_DIRS:
        if f'/{d}/' in filepath:
            return True
    for crate in EXCLUDED_CRATES:
        if f'crates/{crate}/' in filepath:
            return True
    return False

rs_files = sorted([f for f in glob.glob('crates/**/*.rs', recursive=True) if not is_excluded(f)])

def find_block_end(lines, start_idx):
    """Find the end of the Rust item starting at start_idx.
    
    Returns the index of the line AFTER the item ends.
    Handles:
    - Single-line items (ending with ;)
    - Block items with balanced braces {}
    - Nested braces inside strings (best-effort)
    """
    i = start_idx
    if i >= len(lines):
        return i

    brace_count = 0
    in_block = False

    while i < len(lines):
        line = lines[i]
        # Simple approach: count braces, ignoring those in string literals
        # This is best-effort and handles the vast majority of cases

        j = 0
        in_string = False
        string_char = None
        escaped = False

        while j < len(line):
            ch = line[j]

            if escaped:
                escaped = False
                j += 1
                continue

            if ch == '\\':
                escaped = True
                j += 1
                continue

            if in_string:
                if ch == string_char:
                    in_string = False
                j += 1
                continue

            if ch in ('"', "'"):
                in_string = True
                string_char = ch
                j += 1
                continue

            if ch == '/' and j + 1 < len(line) and line[j+1] == '/':
                # Line comment - rest of line is comment
                break

            if ch == '{':
                brace_count += 1
                in_block = True
            elif ch == '}':
                brace_count -= 1

            j += 1

        i += 1

        if in_block and brace_count <= 0:
            return i

        # If we haven't started a block and the line ends with ;, it's a single-line item
        if not in_block:
            stripped = line.rstrip()
            if stripped.endswith(';') and '{' not in stripped:
                return i
            # Also handle 'use ...;' style
            if stripped.endswith(';') and brace_count == 0:
                return i

    return i

def remove_windows_cfg_block(lines, cfg_line_idx):
    """Remove a #[cfg(target_os = "windows")] or #[cfg(windows)] attribute
    and the code block it gates.
    Returns (new_lines_with_block_removed, next_line_idx)."""
    block_end = find_block_end(lines, cfg_line_idx + 1)
    # Return lines without cfg_line_idx..block_end
    return block_end

def simplify_cfg_condition(cond_str):
    """Given a cfg condition string (inside #[cfg(...)]), remove windows-related
    conditions and simplify.
    Returns simplified condition string, or None if the condition becomes always-false."""
    # Handle: not(target_os = "windows") -> always true, remove attr
    if cond_str == 'not(target_os = "windows")':
        return "ALWAYS_TRUE"

    # Handle: target_os = "windows" -> always false, remove block
    if cond_str == 'target_os = "windows"' or cond_str == 'windows':
        return "ALWAYS_FALSE"

    # Handle: not(any(...windows...))
    m = re.match(r'not\(any\((.*)\)\)', cond_str)
    if m and 'target_os = "windows"' in m.group(1):
        inner = m.group(1)
        inner = re.sub(r',\s*target_os = "windows"', '', inner)
        inner = re.sub(r'target_os = "windows",\s*', '', inner)
        items = [x.strip() for x in inner.split(',') if x.strip()]
        if len(items) == 0:
            return "ALWAYS_TRUE"  # not(any()) = not(false) = true
        elif len(items) == 1:
            return f'not({items[0]})'
        else:
            return f'not(any({", ".join(items)}))'

    # Handle: any(...windows...)
    m = re.match(r'any\((.*)\)', cond_str)
    if m and 'target_os = "windows"' in m.group(1):
        inner = m.group(1)
        inner = re.sub(r',\s*target_os = "windows"', '', inner)
        inner = re.sub(r'target_os = "windows",\s*', '', inner)
        items = [x.strip() for x in inner.split(',') if x.strip()]
        if len(items) == 0:
            return "ALWAYS_FALSE"  # any() = false
        elif len(items) == 1:
            return items[0]
        else:
            return f'any({", ".join(items)})'

    # Handle: all(target_os = "windows", ...) -> ALWAYS_FALSE (windows never matches)
    m = re.match(r'all\((.*)\)', cond_str)
    if m and 'target_os = "windows"' in m.group(1):
        return "ALWAYS_FALSE"

    # Handle: not(all(target_os = "windows", ...)) -> ALWAYS_TRUE
    m = re.match(r'not\(all\((.*)\)\)', cond_str)
    if m and 'target_os = "windows"' in m.group(1):
        return "ALWAYS_TRUE"

    # Handle: any(unix, windows) -> unix
    if cond_str == 'any(unix, windows)':
        return 'unix'
    if cond_str == 'any(windows, unix)':
        return 'unix'

    # Handle: any(..., all(target_os = "windows", ...), ...)
    # The all(target_os = "windows", ...) arm is always false, so remove it from any()
    # This handles complex cases like:
    #   any(all(target_os = "windows", target_env = "gnu"), target_os = "freebsd")
    #   -> target_os = "freebsd"
    if 'target_os = "windows"' in cond_str:
        # Remove all(...) sub-expressions that contain target_os = "windows"
        # This is a simplified approach: remove comma-separated items containing
        # 'all(target_os = "windows"' from any() or not(any())
        result = _remove_windows_arms_from_any(cond_str)
        if result is not None:
            return result

    return None  # No simplification needed or not recognized


def _remove_windows_arms_from_any(cond_str):
    """Remove arms containing 'target_os = "windows"' from any() expressions,
    including all(target_os = "windows", ...) arms.
    Handles nested any()/not(any()) etc."""

    # Handle not(any(...))
    m = re.match(r'not\(any\((.*)\)\)', cond_str, re.DOTALL)
    if m:
        inner = m.group(1)
        # Split on commas that are not inside nested parens
        arms = _split_any_arms(inner)
        remaining = [a for a in arms if 'target_os = "windows"' not in a]
        if len(remaining) == len(arms):
            return None  # Nothing removed
        if len(remaining) == 0:
            return "ALWAYS_TRUE"  # not(any()) = true
        elif len(remaining) == 1:
            return f'not({remaining[0].strip()})'
        else:
            return f'not(any({", ".join(a.strip() for a in remaining)}))'

    # Handle any(...)
    m = re.match(r'any\((.*)\)', cond_str, re.DOTALL)
    if m:
        inner = m.group(1)
        arms = _split_any_arms(inner)
        remaining = [a for a in arms if 'target_os = "windows"' not in a]
        if len(remaining) == len(arms):
            return None  # Nothing removed
        if len(remaining) == 0:
            return "ALWAYS_FALSE"  # any() = false
        elif len(remaining) == 1:
            return remaining[0].strip()
        else:
            return f'any({", ".join(a.strip() for a in remaining)})'

    return None


def _split_any_arms(s):
    """Split a comma-separated list of cfg predicates, respecting nested parens.
    e.g. 'all(target_os = "windows", target_env = "gnu"), target_os = "freebsd"'
    -> ['all(target_os = "windows", target_env = "gnu")', ' target_os = "freebsd"']
    """
    arms = []
    depth = 0
    current = []
    for ch in s:
        if ch == '(' :
            depth += 1
            current.append(ch)
        elif ch == ')':
            depth -= 1
            current.append(ch)
        elif ch == ',' and depth == 0:
            arms.append(''.join(current))
            current = []
        else:
            current.append(ch)
    if current:
        arms.append(''.join(current))
    return arms

def read_full_cfg_attr(lines, start_idx):
    """Read a potentially multi-line #[cfg_attr(...)] or #![cfg_attr(...)] attribute.
    Returns (full_attr_text, end_idx) where end_idx is the line after the attribute."""
    i = start_idx
    attr_text = ''
    paren_depth = 0
    bracket_depth = 0
    found_open_bracket = False
    found_close_bracket = False

    while i < len(lines):
        line = lines[i]
        for ch in line:
            if ch == '[' and not found_close_bracket:
                bracket_depth += 1
                found_open_bracket = True
            elif ch == ']':
                bracket_depth -= 1
                if found_open_bracket and bracket_depth == 0:
                    found_close_bracket = True
            elif found_open_bracket and not found_close_bracket:
                if ch == '(':
                    paren_depth += 1
                elif ch == ')':
                    paren_depth -= 1
        attr_text += line if not attr_text else line
        i += 1
        if found_close_bracket:
            break

    return attr_text, i


def read_full_cfg(lines, start_idx):
    """Read a potentially multi-line #[cfg(...)] attribute.
    Returns (full_attr_text, indent, condition_str, end_idx).
    end_idx is the index of the line AFTER the attribute ends."""
    i = start_idx
    # Collect all lines until we find the closing ]
    collected = []
    i = start_idx
    bracket_depth = 0
    paren_depth = 0
    found_content = False

    while i < len(lines):
        line = lines[i]
        collected.append(line)
        for ch in line:
            if ch == '#':
                found_content = True
            if found_content:
                if ch == '[':
                    bracket_depth += 1
                elif ch == ']':
                    bracket_depth -= 1
                elif ch == '(' and bracket_depth > 0:
                    paren_depth += 1
                elif ch == ')' and bracket_depth > 0:
                    paren_depth -= 1
        i += 1
        if found_content and bracket_depth == 0 and paren_depth == 0:
            break

    full_text = ''.join(collected)
    # Extract the indent and condition
    first_line = lines[start_idx]
    indent_match = re.match(r'^(\s*)', first_line)
    indent = indent_match.group(1) if indent_match else ''

    # Extract condition from the full text
    cond_match = re.search(r'#\[cfg\((.+)\)\]', full_text, re.DOTALL)
    if cond_match:
        cond_str = cond_match.group(1)
        # Normalize whitespace in the condition
        cond_str = re.sub(r'\s+', ' ', cond_str).strip()
        return full_text, indent, cond_str, i

    return full_text, indent, None, i


stats = {
    'files_changed': 0,
    'blocks_removed': 0,
    'attrs_ungated': 0,
    'cfgs_simplified': 0,
    'multiline_handled': 0,
}

for rs_file in rs_files:
    with open(rs_file, 'r') as f:
        lines = f.readlines()

    original_text = ''.join(lines)
    new_lines = []
    i = 0
    file_changed = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # ----------------------------------------------------------
        # #![cfg_attr(windows, ...)] -> remove
        # ----------------------------------------------------------
        if re.match(r'^#!\s*\[cfg_attr\(windows\b', stripped):
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #![cfg_attr(not(target_os = "windows"), X)] ->#![ X]
        # ----------------------------------------------------------
        m = re.match(r'^(\s*)#!\s*\[cfg_attr\(not\(target_os = "windows"\),\s*(.*)\)\]\s*$', line)
        if m:
            indent = m.group(1)
            inner = m.group(2)
            new_lines.append(f'{indent}#![{inner}]\n')
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
        # -> remove entirely (no-op without Windows)
        # ----------------------------------------------------------
        if re.match(r'^\s*#!\s*\[cfg_attr\(not\(debug_assertions\),\s*windows_subsystem', stripped):
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #[cfg_attr(target_os = "windows", ...)] -> remove (only applies to windows)
        # ----------------------------------------------------------
        if re.match(r'^\s*#\s*\[cfg_attr\(target_os = "windows"', stripped):
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #[cfg_attr(not(target_os = "windows"), X)] -> remove the cfg_attr,
        #   keep the item (X was the modifier like "ignore")
        #   For "ignore": test was ignored on windows, now it should run.
        #   Remove the whole cfg_attr line.
        # ----------------------------------------------------------
        if re.match(r'^\s*#\s*\[cfg_attr\(not\(.*windows', stripped):
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #[cfg_attr(not(any(...windows...)), X)] -> remove
        # ----------------------------------------------------------
        if re.match(r'^\s*#\s*\[cfg_attr\(not\(any\(.*windows', stripped):
            file_changed = True
            stats['attrs_ungated'] += 1
            i += 1
            continue

        # ----------------------------------------------------------
        # #[cfg(CONDITION)] where CONDITION involves windows
        # Handles both single-line and multi-line cfg attributes
        # ----------------------------------------------------------
        # Check if this line starts a #[cfg(...)] or #[cfg(any(...
        cfg_start = re.match(r'^(\s*)#\s*\[cfg\(', line)
        if cfg_start and 'windows' in line:
            # This could be single-line or multi-line
            if ')]' in line:
                # Single-line: #[cfg(CONDITION)]
                m = re.match(r'^(\s*)#\s*\[cfg\((.+)\)\]\s*$', line)
                if m:
                    indent = m.group(1)
                    cond = m.group(2)
                    simplified = simplify_cfg_condition(cond)

                    if simplified is not None:
                        if simplified == "ALWAYS_TRUE":
                            file_changed = True
                            stats['attrs_ungated'] += 1
                            i += 1
                            continue
                        elif simplified == "ALWAYS_FALSE":
                            block_end = find_block_end(lines, i + 1)
                            file_changed = True
                            stats['blocks_removed'] += 1
                            i = block_end
                            continue
                        else:
                            new_lines.append(f'{indent}#[cfg({simplified})]\n')
                            file_changed = True
                            stats['cfgs_simplified'] += 1
                            i += 1
                            continue
            else:
                # Multi-line: read the full attribute
                full_text, indent, cond_str, attr_end = read_full_cfg(lines, i)
                if cond_str is not None:
                    simplified = simplify_cfg_condition(cond_str)
                    if simplified is not None:
                        if simplified == "ALWAYS_TRUE":
                            file_changed = True
                            stats['attrs_ungated'] += 1
                            stats['multiline_handled'] += 1
                            i = attr_end
                            continue
                        elif simplified == "ALWAYS_FALSE":
                            block_end = find_block_end(lines, attr_end)
                            file_changed = True
                            stats['blocks_removed'] += 1
                            stats['multiline_handled'] += 1
                            i = block_end
                            continue
                        else:
                            # Reconstruct single-line attribute with simplified condition
                            new_lines.append(f'{indent}#[cfg({simplified})]\n')
                            file_changed = True
                            stats['cfgs_simplified'] += 1
                            stats['multiline_handled'] += 1
                            i = attr_end
                            continue

        # ----------------------------------------------------------
        # Remove mod declarations for deleted windows module files
        # ----------------------------------------------------------
        if 'remote_server' in rs_file and stripped in ('pub mod windows;', 'mod windows;'):
            file_changed = True
            i += 1
            continue

        if 'xenomorphic_app' in rs_file and 'windows_only_instance' in stripped:
            file_changed = True
            i += 1
            continue

        if 'platform_title_bar' in rs_file and 'platform_windows' in stripped and 'mod' in stripped:
            file_changed = True
            i += 1
            continue

        # If no pattern matched, keep the line
        new_lines.append(line)
        i += 1

    if file_changed:
        text = ''.join(new_lines)
        # Clean up excessive blank lines
        text = re.sub(r'\n{4,}', '\n\n\n', text)
        with open(rs_file, 'w') as f:
            f.write(text)
        stats['files_changed'] += 1
        print(f'  Modified {rs_file}')

print(f"\n  Stats:")
print(f"    Files changed:            {stats['files_changed']}")
print(f"    Windows blocks removed:   {stats['blocks_removed']}")
print(f"    Attributes un-gated:      {stats['attrs_ungated']}")
print(f"    Cfg conditions simplified: {stats['cfgs_simplified']}")
print(f"    Multi-line cfg handled:   {stats['multiline_handled']}")
PYEOF

# ============================================================
# PHASE 5: Handle cfg!(windows) runtime checks
# ============================================================
log "=== Phase 5: Handling cfg!(windows) runtime checks ==="

python3 << 'PYEOF'
import re, glob

EXCLUDED_CRATES = {'gpui_windows', 'windows_resources', 'etw_tracing', 'explorer_command_injector'}

def is_excluded(filepath):
    for crate in EXCLUDED_CRATES:
        if f'crates/{crate}/' in filepath:
            return True
    return False

rs_files = sorted([f for f in glob.glob('crates/**/*.rs', recursive=True) if not is_excluded(f)])

stats = {'files_changed': 0, 'checks_handled': 0, 'unhandled': []}

for rs_file in rs_files:
    with open(rs_file, 'r') as f:
        content = f.read()

    original = content
    lines = content.split('\n')
    new_lines = []
    i = 0
    file_changed = False

    while i < len(lines):
        line = lines[i]

        # Check for cfg!(windows) or cfg!(target_os = "windows") on this line
        if 'cfg!(windows)' in line or 'cfg!(target_os = "windows")' in line:
            # Pattern 1: cfg!(windows) used as a value (not in an if condition)
            # e.g. ShellBuilder::new(&Shell::System, cfg!(windows))
            # -> ShellBuilder::new(&Shell::System, false)
            if ('cfg!(windows)' in line and 'if cfg!(windows)' not in line
                    and 'if cfg!(target_os' not in line
                    and 'else if cfg!(windows)' not in line):
                old_line = line
                line = line.replace('cfg!(windows)', 'false')
                line = line.replace('cfg!(target_os = "windows")', 'false')
                if line != old_line:
                    new_lines.append(line)
                    file_changed = True
                    stats['checks_handled'] += 1
                    i += 1
                    continue

            # Pattern 2: cfg!(not(target_os = "windows")) used as a value
            # e.g. if cfg!(not(target_os = "windows")) { ... }
            # These are harder - flag for manual review

            stats['unhandled'].append(f'{rs_file}:{i+1}: {line.strip()[:100]}')

        new_lines.append(line)
        i += 1

    if file_changed:
        content = '\n'.join(new_lines)
        if content != original:
            with open(rs_file, 'w') as f:
                f.write(content)
            stats['files_changed'] += 1
            print(f'  Auto-fixed cfg!(windows) value uses in {rs_file}')

if stats['unhandled']:
    print(f"\n  {len(stats['unhandled'])} cfg!(windows) conditions need MANUAL review:")
    for entry in stats['unhandled']:
        print(f"    {entry}")

print(f"\n  Stats:")
print(f"    Files changed:   {stats['files_changed']}")
print(f"    Checks handled:  {stats['checks_handled']}")
print(f"    Unhandled:       {len(stats['unhandled'])}")
PYEOF

echo ""
echo "  For unhandled if-conditions, the pattern is always:"
echo "    if cfg!(windows) { A } else { B }  ->  B"
echo "    if cfg!(target_os = \"windows\") { A } else { B }  ->  B"
echo "    if cfg!(not(target_os = \"windows\")) { A } else { B }  ->  A"
echo ""

# ============================================================
# PHASE 6: CI cleanup
# ============================================================
log "=== Phase 6: CI workflow cleanup ==="

if [ -f ".github/workflows/release.yml" ]; then
    python3 << 'PYEOF'
import re

with open('.github/workflows/release.yml', 'r') as f:
    content = f.read()
original = content

# Remove Windows CI job blocks
# YAML job blocks start with "  job_name:" and end at the next top-level key
jobs_to_remove = [
    'run_tests_windows',
    'clippy_windows',
    'bundle_windows_aarch64',
    'bundle_windows_x86_64',
]

for job in jobs_to_remove:
    # Match from the job name line to the next job/section start
    # Jobs are at 2-space indent, their contents at 4+ spaces
    pattern = r'^  ' + re.escape(job) + r':\s*\n(?:    [^\n]*\n|\s*\n)*'
    content = re.sub(pattern, '', content, flags=re.MULTILINE)

# Remove references to Windows jobs in needs: lists
# e.g. needs: [run_tests_linux, run_tests_windows] -> needs: [run_tests_linux]
content = re.sub(r',\s*\w*windows\w*', '', content)
content = re.sub(r'\w*windows\w*,\s*', '', content)
# Clean up empty needs: []
content = re.sub(r'needs:\s*\[\s*\]', 'needs: []', content)

# Remove Windows-specific step references
content = re.sub(r'.*bundle-windows.*\n', '', content)
content = re.sub(r'.*windows.*zip.*\n', '', content)

# Clean up blank lines
content = re.sub(r'\n{3,}', '\n\n', content)

if content != original:
    with open('.github/workflows/release.yml', 'w') as f:
        f.write(content)
    print("  Cleaned .github/workflows/release.yml")
else:
    print("  No changes needed in release.yml")
PYEOF
fi

# ============================================================
# PHASE 7: Remove windows_subsystem attribute from main.rs files
# ============================================================
log "=== Phase 7: Removing windows_subsystem attribute ==="

for f in crates/xenomorphic/src/main.rs crates/auto_update_helper/src/auto_update_helper.rs; do
    if [ -f "$f" ]; then
        if grep -q 'windows_subsystem' "$f" 2>/dev/null; then
            sed -i '' '/cfg_attr.*windows_subsystem/d' "$f"
            echo "  Removed windows_subsystem attr from $f"
        fi
    fi
done

# ============================================================
# PHASE 8: Verification scan - find remaining windows references
# ============================================================
log "=== Phase 8: Verification scan ==="

echo ""
echo "  Remaining 'windows' references in Rust files:"
remaining=$(grep -rn 'target_os.*windows\|cfg.*windows' crates/ --include="*.rs" 2>/dev/null | grep -v "gpui_windows\|windows_resources\|etw_tracing\|explorer_command_injector" | wc -l | tr -d ' ')
echo "    $remaining occurrences in .rs files"

echo ""
echo "  Remaining 'windows' references in Cargo.toml files:"
remaining_toml=$(grep -rn 'windows' crates/ --include="Cargo.toml" 2>/dev/null | grep -v "gpui_windows\|windows_resources\|etw_tracing\|explorer_command_injector" | wc -l | tr -d ' ')
echo "    $remaining_toml occurrences in Cargo.toml files"

# ============================================================
# DONE
# ============================================================
echo ""
log "=========================================="
log "  Automated removal complete!"
log "=========================================="
echo ""
echo -e "${YELLOW}  REMAINING MANUAL STEPS:${NC}"
echo ""
echo "  1. Handle cfg!(windows) if-conditions (see list above)"
echo "     These are runtime if/else blocks like:"
echo "       if cfg!(windows) { A } else { B }  ->  B"
echo "       if cfg!(target_os = \"windows\") { A } else { B }  ->  B"
echo "     Read each one carefully before editing."
echo ""
echo "  2. Remove extension_builder.rs Windows match arm:"
echo "     crates/extension/src/extension_builder.rs:38"
echo "     all(target_os = \"windows\", target_arch = \"x86_64\") => Some(\"wasi-sdk-...windows.tar.gz\")"
echo "     Remove this match arm and the _ => None fallback may need updating"
echo ""
echo "  3. Verify gpui/build.rs - remove the windows-manifest feature code"
echo "     Remove the #[cfg(feature = \"windows-manifest\")] block"
echo ""
echo "  4. Remove 'embed-resource' build dep from gpui/Cargo.toml if only used for Windows"
echo ""
echo "  5. Run: cargo check"
echo "     Fix any remaining compilation errors."
echo "     Common fixes: remove unused imports, dead code warnings"
echo ""
echo "  6. Run: cargo test --workspace (fix test failures)"
echo ""
echo "  7. Final sweep: grep for remaining 'windows' references:"
echo "     grep -rn 'target_os.*\"windows\"' crates/ --include='*.rs'"
echo "     grep -rn 'windows' crates/ --include='Cargo.toml'"
echo ""
echo -e "${GREEN}  Tip: Use 'git diff --stat' to review all changes,"
echo "       'git diff' to see details, and"
echo "       'git checkout .' to revert if something went wrong.${NC}"
echo ""
