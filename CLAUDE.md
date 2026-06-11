# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`gren-cli` is a Gren **package** (`youruser/cli`) for declarative command-line
argument parsing, extracted from the Gren compiler's own CLI. It exposes three
modules: `Cli.Parser`, `Cli.PrettyPrinter`, and `Cli.Program`. Target Gren is
`0.6.x` (`platform: node`).

## Commands

Validation is done by compiling and by the test suite.

- **Type-check / build the package:** `gren make` (run at repo root).
- **Generate docs (also a strong correctness check — fails on missing/broken
  `@docs`):** `gren docs`.
- **Run the test suite** (`tests/`, a `node` application that depends on the
  package via `"youruser/cli": "local:../"`):
  ```bash
  cd tests
  ./run-tests.sh   # gren make Main --output=app && node app
  ```
  Modeled on the `compiler-node` test harness. `tests/src/Main.gren`
  wires the suites into `Test.Runner.Node`; `Test.Cli.Parser` covers command
  dispatch, arg arities, and the flag tokenizer, and `Test.Cli.PrettyPrinter`
  covers the `Document` renderer. Uses `gren-lang/test` +
  `gren-lang/test-runner-node`. The build artifact (`tests/app`) and
  `tests/gren_packages/` are gitignored.
- **Exit-code integration test:** `tests/exit-codes.sh`. `Cli.Program` does I/O
  and sets the process exit code, so it can't be covered by the pure test
  suite; this script runs the `with-permissions` example and asserts the exit
  code + stream (stdout/stderr) for each `Outcome` path (`Succeeded` → 0,
  `Failed` → 1 silent, task failure → 1 on stderr).
- **Build and run an example.** `examples/` holds one self-contained `node`
  app per scenario, each depending on the package via
  `"youruser/cli": "local:../../"` and carrying its own `run.sh` (the same
  `gren make Main --output=app && node app "$@"` form as `tests/run-tests.sh`):
  ```bash
  cd examples/one-level
  ./run.sh add "buy milk"
  ./run.sh --help
  ```
  The subdirectories cover the runner styles: `no-subcommand/`
  (`Cli.Program.runRoot` — flags/args, no command word), `one-level/`
  (`Cli.Program.run` + `withCommand`), `two-level/` (`withPrefix`, nested
  sub-commands), `manual/` (`Cli.Parser.run` by hand, custom exit code), and
  `with-permissions/` (`Cli.Program.runWithContext`, a `count <file>` command
  acquiring a `FileSystem.Permission`; also exercises all three `Outcome` exit
  paths — non-empty file → 0, empty file → `Failed`/1, missing file → task
  error/1). Each `run.sh` builds the **module
  name** `Main` (not the path `src/Main.gren`: gren 0.6.5 rejects the path form
  with a `<module-names>` error) into an **executable** `app` (not `app.js`,
  which is a *library module* that exports `Main.init` without calling it, so it
  runs and prints nothing). The built `app` and per-example `gren_packages/`
  are gitignored.

## Architecture

The core contract is purity: parsing is `Array String -> CommandParseResult result`,
a pure function that does **no I/O** and never exits the process. It returns one
of five `CommandParseResult` constructors (`UnknownCommand`, `BadFlags`,
`BadArguments`, `HelpText`, `Success a`); the caller decides what to print and
which exit code to use. `Cli.Program.run` is the opinionated wrapper that does
the obvious thing (errors → stderr + exit 1, help → stdout, success → your
handler). The handler returns a `Task String Cli.Program.Outcome`: succeeding
with `Succeeded` exits 0, succeeding with `Failed` exits 1 *silently* (a failed
check — you printed your own report), and failing the task prints the `String`
to stderr and exits 1. The handler never calls `Node.setExitCode`; that mapping
lives in `applyOutcome`. `Cli.Program` only ever exits 0 or 1 — needing another
code (e.g. 2) means dropping to `Cli.Parser.run` (see `examples/manual/`).
`Cli.Program.runWithContext` is the same, but lets the caller run
their own `Init.await` chain first (to acquire `FileSystem`/terminal/etc.
permissions) and threads the resulting *context* into the handler — `run` is
just `runWithContext` with an empty context. `Cli.Program.runRoot` is the
no-sub-command variant: it takes a single `Command` (not an `App`) and calls
`Cli.Parser.runCommand` — which parses flags/args directly, without consuming a
command word — so a tool can be invoked as `mytool --loud World`. Anything
needing custom exit codes or its own model/update loop skips these wrappers and
matches on `CommandParseResult` directly.

### Three layers, composed by the user

1. **Groups / commands** (`defineGroup`, `withCommand`, `withPrefix`). A
   `GroupParser` is built by *folding* combinators into an immutable value —
   each combinator wraps the previous `parseFn` in a closure that either handles
   its own command word or delegates to the next. `withPrefix` nests a whole
   group under a word (e.g. `mytool package …`), giving `git`/`click`-style
   subcommand trees. `--help` and `--version` are special-cased, not general
   flags: `run` handles both as the first token; `runPrefix` handles `--help`
   right after a prefix word (so `mytool package --help` lists the prefix's
   commands rather than reporting `--help` as an unknown command); and
   `runCommand` handles `--help` anywhere in a command's own tokens. `--version`
   is only intercepted at the top level (`run`), since the version lives on the
   `App`.

2. **Arguments** (`ArgumentParser`). Each parser consumes the *entire*
   positional-args array at once and reports `usage` (a string for the help
   line) plus `positionals` (per-arg help metadata). Combinators: `noArgs`,
   `oneArg`/`twoArgs`/`threeArgs` (exact arity), `optionalArg` (`?` → `Maybe`),
   `zeroOrMoreArgs` (`*`), `oneOrMoreArgs` (`+`), plus `mapArgs` and `oneOfArgs`
   (tries branches in order; used to fake mixed/variable arity). **Key
   limitation:** because each `ArgumentParser` swallows the whole array, you
   cannot express "one required then rest variadic" (`<a> [rest...]`) — that
   needs a sequential redesign of `ArgumentParser`.

3. **Flags** (`FlagParser`). Built type-safely: `initFlags` seeds a record
   constructor, then `toggle` (adds `Bool`) and `flag` (adds `Maybe value`)
   chain on, each filling one constructor argument so the final flags record is
   compiler-checked. `FlagKind` is a sum type (`Toggle` | `TakesValue { title,
   examples }`) so a toggle structurally cannot carry a value type. Only
   `--long` flags exist; **no short flags** (the tokenizer treats anything not
   starting with `--` as positional). Repeated flags = last-one-wins (no
   count/append). Value flags are always optional (`Maybe`); there is no
   "required option" at the parse layer.

A `Command` ties these together with a `builder : args -> flags -> result` that
bridges parsed input into the user's own command sum type. A `ValueParser`
(`{ singular, plural, fn : String -> Maybe val, examples }`) is the unit of type
conversion and powers both arguments and value flags; built-ins are
`pathParser` and `grenFileParser`.

### Tokenizing (`parseRawTokens` in `Cli.Parser`)

Splits raw tokens into a `Dict String String` of flags plus an args array.
Supports both `--flag=value` and `--flag value` (the bare form peeks at the next
token via `handleBareFlag` and only consumes it if it doesn't look like another
`--flag`), and the `--` separator (stop flag parsing, rest are positional).
Empty-string flag value is the sentinel for "present but no value yet", which
later distinguishes a toggle from a value flag missing its value.

### Pretty printing (`Cli.PrettyPrinter`)

An opaque `Document` ADT (`Empty`, `Text`, `Words`, `Colorized`, `Indented`,
`Block`, `VerticalBlock`) rendered by `toString`. All help and error output is
built from these combinators — `text`, `words` (wraps on word boundaries),
`block` (horizontal), `verticalBlock`, `indent`, `color`/`intenseColor`
(ANSI). The error/help renderers in `Cli.Parser`
(`argumentErrorPrettified`, `flagErrorPrettified`, `commandHelpText`, etc.)
return `Document`s, keeping output formatting separate from I/O.

## Conventions / gotchas

- This is a **package** (`gren.json` `"type": "package"`): every exposed value
  and type needs a `{-| … -}` doc comment and a matching `@docs` entry in the
  module header, or `gren docs` fails. Keep both in sync when adding/removing
  exports.
- `platform: node` is required *only* by `pathParser` / `grenFileParser`
  (`FileSystem.Path`). Dropping those two and the `gren-lang/node` dependency
  would make the package `platform: common` (browser-capable).
- `semanticVersionParser` / `packageNameParser` were intentionally removed from
  the original compiler version to avoid a `gren-lang/compiler-common`
  dependency; re-add them only if building Gren-specific tooling.
- Several features are **intentionally missing** vs. Python `argparse` (short
  flags, count/append, mutually-exclusive groups, required options, mixed
  arity). Before "adding a missing feature," check whether the gap is deliberate
  — many have a documented workaround.
