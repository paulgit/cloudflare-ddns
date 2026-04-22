# Bash/Shell Script Development Guidelines

## Core Principles

Write shell scripts that are correct, portable, and maintainable.
Prefer clarity over cleverness. Every script should be safe to run
in production.

Target `bash` on Linux unless stated otherwise.

---

## AI Collaboration Guidelines

These rules govern how Claude should behave when assisting with
scripts in this project.

- **Ask for clarification**: If more information is needed to write
  or optimise a script, ask for it — unless told to stop asking.
- **Diagnostic code**: If a bug remains unresolved after more than
  three back-and-forth exchanges, offer to add diagnostic code to
  gather more information about the issue.
- **Non-coding questions**: If a question is not about
  coding/software at all, do not answer it initially. Instead,
  point this out and ask if the user wants to switch to a different
  style. If they say no, continue the conversation normally.
- **Retaining external command comments**: If a script calls an
  external command and has comments describing its parameters,
  retain those comments when modifying the script. Adjust them if
  parameters change. Remove them if the command is removed.

---

## Design

For scripts with complex logic, explore multiple design options
before settling on one. Briefly describe the options considered and
justify the chosen approach in the script's header comment block.

---

## After Every Edit

Run both checks after **every** file modification — no exceptions:

```bash
# 1. Syntax check (fast, catches parse errors immediately)
bash -n path/to/script.sh

# 2. Static analysis (catches bugs, style issues, unsafe patterns)
shellcheck path/to/script.sh
```

If either check fails, fix all reported issues before proceeding.
Do not move on to the next change while errors or warnings remain.

### Installing ShellCheck

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
apt-get install shellcheck

# Check it's available
shellcheck --version
```

---

## Script Structure

Every script must open with:

```bash
#!/usr/bin/env bash
# ============================================================
# script-name.sh
#
# High-level description of what the script does.
#
# Disclaimer: No warranties are given for correct function.
# Written by: Paul Git and Claude AI
#
# Variable names are uppercased if the variable is read-only
# or if it is an external variable.
# ============================================================

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

IFS=$'\n\t'
```

- Always use the long-form `set -o <option>` flags (not `-euo`)
  so the intent of each flag is self-documenting.
- Include the variable-naming note in the header **only** when the
  script contains uppercase variable names.
- `IFS=$'\n\t'` — safer word splitting (avoids space-splitting
  surprises).

---

## Comments and Documentation

Use comments generously throughout the script.

### Header comment block

Every script must have the header comment block shown in
**Script Structure** above. It must include:

1. The script filename.
2. A high-level description of what the script does.
3. Disclaimer line.
4. Author line: `Written by: Paul Git and Claude AI`.
5. If the script uses uppercase variable names, the variable
   naming note.

### Function comment blocks

Every function must be preceded by a comment block in this form:

```bash
# ============================================================
# function_name
#   What the function does (one or two sentences).
#   Input:  $1 - description of first argument
#           $2 - description of second argument
#   Output: what the function writes to stdout/stderr,
#           or what side-effects it produces
#   Called by: function_a, main, trap on EXIT
# ============================================================
```

### Global variable comment

Precede the block of global variable definitions with a single
comment, e.g.:

```bash
# ------------------------------------------------------------
# Global read-only variables
# ------------------------------------------------------------
readonly CONFIG_DIR="/etc/myapp"
```

One comment for the group is sufficient; do not comment each
variable individually unless something non-obvious needs
explaining.

---

## Variables and Quoting

### Quoting

Always quote variable expansions to prevent word splitting and
glob expansion:

```bash
# Good
echo "$variable"
cp "$source" "$destination"

# Bad — breaks on spaces and special characters
echo $variable
cp $source $destination
```

### Naming

- Variable and parameter names must indicate their respective
  functions. A reader should understand the purpose of a variable
  from its name alone.
- If a variable's value expresses a quantity with a unit of
  measurement, include the unit in the name:

  ```bash
  # Good
  retry_delay_in_seconds=30

  # Bad
  retry_delay=30
  ```

### Uppercase convention

Uppercase a variable name when **either** of these conditions
applies:

1. The variable is **read-only** — its value is set only once
   (e.g., at definition) and is not derived from user input or
   from other external variables.
2. The variable is an **external variable** (an environment
   variable exported to or inherited from the environment).

Lowercase is used for all other variables, including those set
from user input, function arguments, or values that change during
execution.

```bash
# Read-only: set once, not from user input → UPPERCASE
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAX_RETRIES=5

# External / environment variable → UPPERCASE
: "${HOME:?HOME must be set}"

# Set from user input or changes during execution → lowercase
output_file="$1"
current_retry=0
```

### readonly

Make every variable that can be made `readonly`, `readonly`. This
applies especially to constants and to values computed once at
startup:

```bash
readonly CONFIG_DIR="/etc/myapp"
readonly SCRIPT_NAME
SCRIPT_NAME="$(basename "$0")"
```

### Spaces around `=`

- In variable **assignments**, never use spaces around `=`:
  `var=value` (not `var = value`).
- In `[[ ]]` **comparisons**, always put spaces around `==`:
  `[[ "$a" == "$b" ]]`.

### Command substitution

Prefer `$()` over backticks:

```bash
# Good
result=$(command)

# Avoid
result=`command`
```

### local

Use `local` for all variables inside functions. Prefer local over
global variables wherever possible.

---

## Functions

### General rules

- Break logic into named functions. Keep `main()` as the entry
  point, called at the end of the script: `main "$@"`.
- Use functions generously. Any function body that exceeds
  **30 non-blank lines** must be split into smaller functions.
- Always use the `function` keyword when defining a function:

  ```bash
  function my_function() {
    ...
  }
  ```

### Naming

- Function names must be **lowercase with underscores** to
  separate words (Google Shell Style Guide).
- If a function both processes data **and** produces output
  (writes to stdout/stderr), its name must reflect both
  responsibilities:

  ```bash
  # Bad — name implies only processing
  function process_results() { ... }

  # Good — name reveals that output is also produced
  function process_and_display_results() { ... }
  ```

### Echo and stdout

If a function uses `echo` (or `printf`) with the intent of sending
output to the terminal (stdout), verify that the function is not
being called via command substitution (`$(...)`) — if it is, that
output will be captured by the caller instead of reaching the
terminal. Add a note in the function's comment block when this
distinction matters.

---

## Help and Usage

Every script must support `-h` / `--help` flags that print usage
information and exit with code 0.

Usage output must be implemented in a dedicated function (e.g.,
`show_usage`). The usage text must:

1. Describe the function of the script.
2. List all arguments with descriptions.
3. List all options/flags with descriptions.
4. Show the expected invocation syntax.

```bash
# ============================================================
# show_usage
#   Prints usage information to stdout.
#   Input:  none
#   Output: usage text to stdout
#   Called by: main
# ============================================================
function show_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [-h|--help] <arg1> [arg2]

One-line description of what the script does.

Arguments:
  arg1    Description of the first argument.
  arg2    Optional second argument (default: value).

Options:
  -h, --help    Show this help message and exit.
EOF
}
```

---

## Error Handling

Check for required tools at the start of the script:

```bash
function check_dependencies() {
  local tool
  for tool in curl jq; do
    if ! command -v "${tool}" &>/dev/null; then
      echo "Error: '${tool}' is required but not installed." >&2
      exit 1
    fi
  done
}
```

Provide meaningful error messages and exit with non-zero codes on
failure.

### Cleanup trap

If the script creates temporary files, starts background
processes, or performs any other action that requires cleanup on
exit, implement a `cleanup()` function and register it on both
`EXIT` and `ERR`:

```bash
# ============================================================
# cleanup
#   Removes temporary files and other resources on exit.
#   Input:  none
#   Output: none
#   Called by: trap on EXIT, trap on ERR
# ============================================================
function cleanup() {
  [[ -f "${tmp_file:-}" ]] && rm -f "${tmp_file}"
}

trap cleanup EXIT ERR
```

---

## Input Validation

Validate all arguments before doing any work. Where a parameter's
expected type can be inferred (e.g., a path, an IP address, an
integer), validate it accordingly — as you would in a typed
language:

```bash
if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "$0") <source> <destination>" >&2
  exit 1
fi

source="$1"
destination="$2"

if [[ ! -f "$source" ]]; then
  echo "Error: source file '$source' does not exist." >&2
  exit 1
fi
```

Never trust external input. Always validate before use.

---

## Performance

Write performant code. Do not perform an operation more than once
if the result can be computed once and reused. For example, do not
call the same external command multiple times when a single call
and a variable assignment would suffice.

---

## Conditionals

Use `[[ ]]` instead of `[ ]` or `test` for conditionals in bash —
it is safer and more expressive:

```bash
# Good
if [[ "$var" == "value" ]]; then ...
if [[ -f "$file" ]]; then ...

# Avoid
if [ "$var" = "value" ]; then ...
if test -f "$file"; then ...
```

---

## Portability

- Target `bash` explicitly (not `/bin/sh`) unless POSIX
  portability is a strict requirement.
- Avoid bash 4+ features (associative arrays, etc.) if the script
  must run on macOS without Homebrew. For Linux-only scripts,
  bash 4.4+ features (e.g., `mapfile`, `local -n`) are acceptable.
- Use `#!/usr/bin/env bash` rather than `#!/bin/bash` for better
  portability across environments.

---

## Logging and Output

- Send informational/debug output to stderr (`>&2`) to keep stdout
  clean for data.
- Use a consistent `log()` or `info()`/`warn()`/`error()` function
  rather than bare `echo` for log messages.
- Never use `echo` for error messages — use `echo >&2` or a
  dedicated error function.

---

## Security

- Never use `eval` unless absolutely unavoidable; if used, document
  why clearly.
- Sanitise any external input before using it in commands.
- Use `mktemp` for temporary files, never hardcoded paths like
  `/tmp/myfile`.
- Avoid storing secrets in variables that get printed; mask them
  in log output.

---

## Style

### Line length

Maximum line length is **80 characters** (Google Shell Style
Guide). For literal strings longer than 80 characters, use a
here-document or an embedded newline where possible.

---

## ShellCheck Directives

When a ShellCheck warning is a false positive, suppress it with an
inline directive and a comment explaining why:

```bash
# shellcheck disable=SC2034  # VAR is exported for child processes
export VAR="value"
```

Never suppress warnings without understanding them first.

---

## Checklist Before Marking a Script Complete

- [ ] `bash -n script.sh` passes with no output
- [ ] `shellcheck script.sh` passes with no warnings
- [ ] Script has the standard header comment block
      (description, disclaimer, author, var-naming note if needed)
- [ ] Script uses long-form `set -o errexit / nounset / pipefail`
- [ ] All functions have a comment block (what, input, output,
      callers)
- [ ] Global variables are preceded by a group comment
- [ ] All variables that can be `readonly` are `readonly`
- [ ] Uppercase naming applied correctly (read-only and external
      variables only)
- [ ] No function body exceeds 30 non-blank lines
- [ ] All function definitions use the `function` keyword
- [ ] Script supports `-h` / `--help` via a `show_usage()` function
- [ ] All variables are quoted
- [ ] `local` used for all function-scoped variables
- [ ] Required commands are checked at startup
- [ ] Temporary files use `mktemp` and are cleaned up via
      `trap cleanup EXIT ERR`
- [ ] Lines are ≤ 80 characters
- [ ] Units included in variable names where applicable
- [ ] Script has been tested with edge-case inputs (spaces in
      filenames, empty values, missing files)
