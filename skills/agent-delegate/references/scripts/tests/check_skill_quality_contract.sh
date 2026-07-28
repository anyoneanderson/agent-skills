#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUALITY="$TEST_DIR/check_skill_quality.sh"
REPO_ROOT="$(git -C "$TEST_DIR" rev-parse --show-toplevel)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skill-quality-contract.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT TERM INT HUP

new_fixture() {
  local case_name="$1" skill_dir
  skill_dir="$WORK_DIR/$case_name/fixture-skill"
  mkdir -p "$skill_dir"
  printf '%s\n' \
    '---' \
    'name: fixture-skill' \
    'description: |' \
    '  English triggers: "validate fixture".' \
    '  日本語トリガー: 「fixtureを検査」' \
    'license: MIT' \
    '## 日本語のYAMLコメント' \
    '---' \
    '# fixture-skill — Validate Markdown Headings' \
    '' \
    '## Language Rules' \
    '' \
    'Respond in the user language.' \
    '' \
    '## Execution Flow' \
    '' \
    'Validate the fixture.' > "$skill_dir/SKILL.md"
  printf '%s\n' "$skill_dir/SKILL.md"
}

expect_pass() {
  local label="$1" file="$2"
  bash "$QUALITY" "$file" >/dev/null || {
    printf 'CONTRACT_FAIL\t%s\texpected pass\n' "$label" >&2
    return 1
  }
}

expect_failure() {
  local label="$1" file="$2" expected="$3" output rc
  set +e
  output="$(bash "$QUALITY" "$file" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 1 ] || ! printf '%s\n' "$output" | grep -q "$expected" ||
      ! printf '%s\n' "$output" | grep -Fqx $'SKILL_QUALITY_SUMMARY\tFAIL\t1'; then
    printf 'CONTRACT_FAIL\t%s\texpected failure containing: %s\n%s\n' "$label" "$expected" "$output" >&2
    return 1
  fi
}

bash "$QUALITY" \
  "$REPO_ROOT/skills/cmux-second-opinion/SKILL.md" \
  "$REPO_ROOT/skills/mcp-convert/SKILL.md" \
  "$REPO_ROOT/skills/skill-suggest/SKILL.md" >/dev/null || {
    printf 'CONTRACT_FAIL\tactual-skills\texpected pass\n' >&2
    exit 1
  }

fenced_fixture="$(new_fixture fenced-headings)"
cat >> "$fenced_fixture" <<'EOF'

````markdown
## 日本語の出力例
`````

   ~~~text
### 日本語の出力例
   ~~~~

```text
``` trailing text is code, not a closing fence
## 日本語の出力例
```
EOF
expect_pass fenced-headings "$fenced_fixture"

real_heading_fixture="$(new_fixture real-heading)"
printf '\n## 日本語の実見出し\n' >> "$real_heading_fixture"
expect_failure real-heading "$real_heading_fixture" 'headings must be English'

indented_heading_fixture="$(new_fixture indented-heading)"
printf '\n   ## 日本語の実見出し\n' >> "$indented_heading_fixture"
expect_failure indented-heading "$indented_heading_fixture" 'headings must be English'

indented_code_fixture="$(new_fixture four-space-heading)"
printf '\n    ## 日本語のコード例\n' >> "$indented_code_fixture"
expect_pass four-space-heading "$indented_code_fixture"

fake_opening_fixture="$(new_fixture four-space-opening)"
cat >> "$fake_opening_fixture" <<'EOF'

    ```markdown
## 日本語の実見出し
    ```
EOF
expect_failure four-space-opening "$fake_opening_fixture" 'headings must be English'

tilde_closer_fixture="$(new_fixture tilde-closer)"
cat >> "$tilde_closer_fixture" <<'EOF'

~~~text
## 日本語の出力例
~~~
## 日本語の実見出し
EOF
expect_failure tilde-closer "$tilde_closer_fixture" 'headings must be English'

long_closer_fixture="$(new_fixture longer-backtick-closer)"
cat >> "$long_closer_fixture" <<'EOF'

````text
## 日本語の出力例
`````
## 日本語の実見出し
EOF
expect_failure longer-backtick-closer "$long_closer_fixture" 'headings must be English'

indented_closer_fixture="$(new_fixture indented-closer)"
cat >> "$indented_closer_fixture" <<'EOF'

```text
## 日本語の出力例
   ```
## 日本語の実見出し
EOF
expect_failure indented-closer "$indented_closer_fixture" 'headings must be English'

marker_match_fixture="$(new_fixture marker-match)"
cat >> "$marker_match_fixture" <<'EOF'

```text
~~~
## 日本語の出力例
```
EOF
expect_pass marker-match "$marker_match_fixture"

reverse_marker_fixture="$(new_fixture reverse-marker-match)"
cat >> "$reverse_marker_fixture" <<'EOF'

~~~text
```
## 日本語の出力例
~~~
EOF
expect_pass reverse-marker-match "$reverse_marker_fixture"

tab_indented_fixture="$(new_fixture tab-indented-code)"
printf '\n\t```markdown\n## 日本語の実見出し\n\t```\n' >> "$tab_indented_fixture"
expect_failure tab-indented-code "$tab_indented_fixture" 'headings must be English'

fenced_title_fixture="$(new_fixture fenced-title)"
awk '$0 == "# fixture-skill — Validate Markdown Headings" { print "Title"; next } { print }' \
  "$fenced_title_fixture" > "$fenced_title_fixture.tmp"
mv "$fenced_title_fixture.tmp" "$fenced_title_fixture"
cat >> "$fenced_title_fixture" <<'EOF'

```markdown
# fixture-skill — Validate Markdown Headings
```
EOF
expect_failure fenced-title "$fenced_title_fixture" 'title must use'

fenced_language_rules_fixture="$(new_fixture fenced-language-rules)"
awk '$0 == "## Language Rules" { print "Language Rules"; next } { print }' \
  "$fenced_language_rules_fixture" > "$fenced_language_rules_fixture.tmp"
mv "$fenced_language_rules_fixture.tmp" "$fenced_language_rules_fixture"
cat >> "$fenced_language_rules_fixture" <<'EOF'

```markdown
## Language Rules
```
EOF
expect_failure fenced-language-rules "$fenced_language_rules_fixture" 'missing Language Rules'

unterminated_fixture="$(new_fixture unterminated-fence)"
cat >> "$unterminated_fixture" <<'EOF'

```text
## 日本語の出力例
EOF
expect_failure unterminated-fence "$unterminated_fixture" 'unclosed fenced code block'

unterminated_frontmatter_fixture="$(new_fixture unterminated-frontmatter)"
awk '$0 == "---" { count++; if (count == 2) next } { print }' \
  "$unterminated_frontmatter_fixture" > "$unterminated_frontmatter_fixture.tmp"
mv "$unterminated_frontmatter_fixture.tmp" "$unterminated_frontmatter_fixture"
expect_failure unterminated-frontmatter "$unterminated_frontmatter_fixture" 'unclosed YAML frontmatter'

printf 'SKILL_QUALITY_CONTRACT_SUMMARY\tPASS\n'
