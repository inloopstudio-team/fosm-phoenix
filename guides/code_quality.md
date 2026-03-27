# Code Quality Guide

This guide covers the code quality tools and practices for FOSM Phoenix.

## Overview

FOSM Phoenix enforces high code quality standards through automated tools:

- **Formatter** - Consistent code style
- **Credo** - Static analysis and best practices
- **Dialyzer** - Type checking and static analysis
- **Git Hooks** - Pre-commit and pre-push validation

## Setup

Install git hooks:

```bash
mix git_hooks.setup
```

Or manually:

```bash
cp .git_hooks/pre-commit .git/hooks/pre-commit
cp .git_hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

## Tools

### Formatter

Enforces consistent code style across the project.

```bash
# Check formatting
mix format --check-formatted

# Fix formatting issues
mix format
```

Configuration: `.formatter.exs`

Key settings:
- Line length: 120 characters
- Import deps for Ecto, Phoenix, and Oban
- Custom locals without parentheses for FOSM DSL

### Credo

Static analysis for code consistency and best practices.

```bash
# Run in strict mode (required for commits)
mix credo --strict

# Run with all checks
mix credo --all

# Generate config
mix credo.gen.config
```

Configuration: `.credo.exs`

Credo checks include:
- **Consistency** - Exception names, line endings, parameter matching
- **Design** - Alias usage, duplicated code, test coverage
- **Readability** - Alias order, max line length, module layout
- **Refactoring** - ABC size, cyclomatic complexity, nesting
- **Warnings** - Unsafe operations, unused code

### Dialyzer

Type analysis and bug detection.

```bash
# Build PLT (Persistent Lookup Table) - first run only
mix dialyzer --plt

# Run analysis
mix dialyzer

# Force rebuild
mix dialyzer --force-check
```

Configuration in `mix.exs`:

```elixir
dialyzer: [
  plt_core_path: "priv/plts",
  plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
]
```

Note: The PLT is cached in `priv/plts/` and should not be committed.

## Git Hooks

### Pre-commit

Runs automatically on `git commit`:
1. Check formatting
2. Run Credo (strict mode)
3. Check compiler warnings

### Pre-push

Runs automatically on `git push`:
1. Check formatting
2. Run Credo (strict mode)
3. Check compiler warnings
4. Run tests
5. Run Dialyzer

## Quality Aliases

Convenient mix aliases for quality checks:

```bash
# Run all quality checks
mix quality

# Fix auto-fixable issues
mix quality.fix

# Setup git hooks
mix git_hooks.setup
```

## CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/ci.yml example
- name: Check Formatting
  run: mix format --check-formatted

- name: Run Credo
  run: mix credo --strict

- name: Check Compiler Warnings
  run: mix compile --warnings-as-errors

- name: Run Dialyzer
  run: mix dialyzer

- name: Run Tests
  run: mix test
```

## Best Practices

### Writing Code

1. **Add typespecs to all public functions**:

   ```elixir
   @spec fire!(struct(), atom(), keyword()) :: {:ok, struct()} | {:error, term()}
   def fire!(record, event_name, opts \\ []) do
     # ...
   end
   ```

2. **Document all public functions**:

   ```elixir
   @doc """
   Fires a lifecycle event on a record.

   ## Parameters
     * `record` - The record to transition
     * `event_name` - The event to fire
     * `opts` - Options including `:actor` and `:context`

   ## Returns
     * `{:ok, updated_record}` - Successful transition
     * `{:error, reason}` - Failed transition

   ## Examples
       {:ok, invoice} = Fosm.Invoice.fire!(invoice, :pay, actor: current_user)
   """
   ```

3. **Use pattern matching** over conditionals when possible

4. **Keep functions small and focused** (aim for < 20 lines)

### Common Credo Warnings to Fix

1. **Module attribute ordering** - Follow the strict module layout:
   - `@moduledoc`
   - `@behaviour`
   - `use`, `import`, `alias`, `require`
   - `@defstruct`, `@type`, `@typedoc`
   - Public functions
   - Private functions

2. **Alias ordering** - Group and sort aliases:

   ```elixir
   # Good
   alias Fosm.Lifecycle.Definition
   alias Fosm.Lifecycle.EventDefinition
   alias Fosm.Lifecycle.StateDefinition

   # Also acceptable
   alias Fosm.Lifecycle.{Definition, EventDefinition, StateDefinition}
   ```

3. **Max line length** - Break long lines:

   ```elixir
   # Instead of:
   def long_function_name(with_many, arguments, that_exceed, the_line_limit), do: body

   # Use:
   def long_function_name(
     with_many,
     arguments,
     that_exceed,
     the_line_limit
   ) do
     body
   end
   ```

### Common Dialyzer Warnings

1. **Type mismatches** - Ensure typespecs match implementation
2. **Unknown functions** - Add proper imports/aliases
3. **Contract violations** - Check function contracts match calls

## Troubleshooting

### Credo

```bash
# Disable a check for a specific line
# credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
some_long_line()

# Disable for a file
# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength
```

### Dialyzer

Slow first run? The PLT needs to be built. Subsequent runs are fast.

```bash
# Check PLT status
mix dialyzer --plt_info

# PLT location
ls priv/plts/
```

### Formatter

For files that shouldn't be formatted:

```elixir
# .formatter.exs
[
  inputs: [
    # ...
    "{config,lib,test}/**/*.{ex,exs}",
    # Exclude specific files
    "!lib/some_special_file.ex"
  ]
]
```

## IDE Integration

### VS Code

Recommended extensions:
- ElixirLS (includes formatter)
- Credo (inline warnings)

### JetBrains (IntelliJ/WebStorm)

- Elixir plugin includes formatter support

### Vim/Neovim

With `coc-elixir` or `elixir-ls`:

```vim
" Format on save
autocmd BufWritePost *.ex,*.exs silent !mix format %
```

## Related Guides

- [Getting Started](getting_started.md)
- [Architecture Overview](architecture.md)
- [Contributing](contributing.md)
