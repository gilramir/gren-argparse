# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`gren-argparse` is a Gren **package** (`gilramir/gren-argparse`) for declarative command-line
argument parsing, extracted from the Gren compiler's own CLI. (This is the directory
formerly named `gren-cli`.) It exposes three
modules: `Argparse.Parser`, `Argparse.PrettyPrinter`, and `Argparse.Program`. Target Gren is
`0.6.x` (`platform: node`). Its first consumer is the sibling `gren-format` repo —
the standalone `gren-format` CLI depends on it locally (`gilramir/gren-argparse: local:../gren-argparse`).

## Commands

Validation is done by compiling and by the test suite.

- **Type-check / build the package:** `gren make` (run at repo root).
- **Generate docs (also a strong correctness check — fails on missing/broken
  `@docs`):** `gren docs`.
- **Run the test suite** (`tests/`, a `node` application that depends on the
  package via `"gilramir/gren-argparse": "local:../"`):
  ```bash
  cd tests
  ./run-tests.sh   # gren make Main --output=app && node app
  ```
  Modeled on the `compiler-node` test harness. `tests/src/Main.gren`
  wires the suites into the runner; `Test.Argparse.Parser` covers command
  dispatch, arg arities, and the flag tokenizer, and `Test.Argparse.PrettyPrinter`
  covers the `Document` renderer. These two are pure `Test.Test` suites; `Main`
  runs everything through `blaix/gren-effectful-tests`
  (`Test.Runner.Effectful`), lifting the pure suites with `Effectful.wrap` so
  they sit alongside the I/O-driven `Argparse.Program` suite. Uses `gren-lang/test` +
  `gren-lang/test-runner-node` + `blaix/gren-effectful-tests`. The build
  artifact (`tests/app`) and `tests/gren_packages/` are gitignored.
- **Exit-code integration tests:** `Test.Argparse.Program`. `Argparse.Program` does I/O
  and sets the process exit code, so it can't be covered by a *pure* suite —
  awaiting its work in the test process would clobber the runner's own exit
  code. Instead this suite uses `Test.Runner.Effectful`'s `await`/`awaitError`
  to drive built examples as child processes (`ChildProcess.run`), asserting the
  exit code + stream (stdout/stderr) for each `Failure` path (`Task.succeed {}` → 0,
  `ExitFailure` → 1 silent, `ExitMessage` → 1 on stderr). The same three assertions
  run against both context-acquiring runners — `with-permissions`
  (`runWithContext`, invoked `count <file>`) and `root-with-permissions`
  (`runRootWithContext`, invoked rootless `<file>`) — parameterized by example
  dir and whether a `count` command word precedes the path. Because it execs the
  examples, `run-tests.sh` builds both before building/running the test app.
  (This replaced the old `tests/exit-codes.sh` bash script.)
- **Build and run an example.** `examples/` holds one self-contained `node`
  app per scenario, each depending on the package via
  `"gilramir/gren-argparse": "local:../../"` and carrying its own `run.sh` (the same
  `gren make Main --output=app && node app "$@"` form as `tests/run-tests.sh`):
  ```bash
  cd examples/one-level
  ./run.sh add "buy milk"
  ./run.sh --help
  ```
  The subdirectories cover the runner styles: `no-subcommand/`
  (`Argparse.Program.runRoot` — flags/args, no command word), `one-level/`
  (`Argparse.Program.run` + `withCommand`), `two-level/` (`withPrefix`, nested
  sub-commands), `manual/` (`Argparse.Parser.run` by hand, custom exit code), and
  `with-permissions/` (`Argparse.Program.runWithContext`, a `count <file>` command
  acquiring a `FileSystem.Permission`; also exercises all three `Failure` exit
  paths — non-empty file → 0, empty file → `ExitFailure`/1, missing file →
  `ExitMessage`/1), and `root-with-permissions/` (`Argparse.Program.runRootWithContext` — the
  rootless `wc <file>` tool acquiring a `FileSystem.Permission`, i.e.
  `runRoot` + context; same three `Failure` paths). Each `run.sh` builds the **module
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
which exit code to use. `Argparse.Program.run` is the opinionated wrapper that does
the obvious thing (errors → stderr + exit 1, help → stdout, success → your
handler). The handler returns a `Task Argparse.Program.Failure {}`: `Task.succeed {}`
exits 0; `Task.fail ExitFailure` exits 1 silently (you already printed your report);
`Task.fail (ExitMessage msg)` prints `msg` to stderr and exits 1; `Task.fail (ExitValue n)`
exits with code `n`; `Task.fail (ExitMessageValue { message, value })` prints to stderr
and exits with the given code. The handler never calls `Node.setExitCode`; that mapping
lives in `applyFailure`. Only programs needing a full model/update loop need to drop to
`Argparse.Parser.run` (see `examples/manual/`).
`Argparse.Program.runWithContext` is the same, but lets the caller run
their own `Init.await` chain first (to acquire `FileSystem`/terminal/etc.
permissions) and threads the resulting *context* into the handler — `run` is
just `runWithContext` with an empty context. `Argparse.Program.runRoot` is the
no-sub-command variant: it takes a single `Command` (not an `App`) and calls
`Argparse.Parser.runCommand` — which parses flags/args directly, without consuming a
command word — so a tool can be invoked as `mytool --loud World`.
`Argparse.Program.runRootWithContext` is `runRoot` + context — the rootless analog of
`runWithContext` (and `runRoot` is just it with an empty context, mirroring how
`run` relates to `runWithContext`). So the four `Argparse.Program` runners form a 2×2:
{command-word `run` / rootless `runRoot`} × {no context / `…WithContext`}.
Anything needing custom exit codes or its own model/update loop skips these
wrappers and matches on `CommandParseResult` directly.

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
   `runCommand` handles `--help` anywhere in a command's own tokens. `-h` is
   honored as an alias for `--help` at all three sites — since it doesn't start
   with `--`, the tokenizer leaves it in `args`, so `runCommand` scans the raw
   tokens (`Array.member "-h"`) rather than the flags dict. `--version` is only
   intercepted at the top level (`run`), since the version lives on the `App`.

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
   examples }`) so a toggle structurally cannot carry a value type. A flag's
   name is a `FlagName` — `LongOnly "all"` (`--all`), `ShortOnly "a"` (`-a`), or
   `Both { long = "all", short = "a" }` (both spellings, help shows `--all, -a`).
   The tokenizer builds a `shortAliasMap` from the `ShortOnly`/`Both` names and
   resolves a `-x` token to its canonical (long, for `Both`) key; anything else
   not starting with `--` is positional. `--help`/`-h` is still special-cased
   separately (it's intercepted before flag parsing, via `Both`-style handling
   in `run`/`runPrefix`/`runCommand`), so a command needn't declare it. Repeated
   flags = last-one-wins (no count/append). Value flags are always optional
   (`Maybe`); there is no "required option" at the parse layer.

A `Command` ties these together with a `builder : args -> flags -> result` that
bridges parsed input into the user's own command sum type. A `ValueParser`
(`{ label, fn : String -> Maybe val, examples }`) is the unit of type
conversion and powers both arguments and value flags; the built-in is
`pathParser`.

### Tokenizing (`parseRawTokens` in `Argparse.Parser`)

Splits raw tokens into a `Dict String String` of flags plus an args array.
Supports both `--flag=value` and `--flag value` (the bare form peeks at the next
token via `handleBareFlag` and only consumes it if it doesn't look like another
`--flag`), and the `--` separator (stop flag parsing, rest are positional).
Empty-string flag value is the sentinel for "present but no value yet", which
later distinguishes a toggle from a value flag missing its value.

### Pretty printing (`Argparse.PrettyPrinter`)

An opaque `Document` ADT (`Empty`, `Text`, `Words`, `Colorized`, `Indented`,
`Block`, `VerticalBlock`) rendered by `toString`. All help and error output is
built from these combinators — `text`, `words` (wraps on word boundaries),
`block` (horizontal), `verticalBlock`, `indent`, `color`/`intenseColor`
(ANSI). The error/help renderers in `Argparse.Parser`
(`argumentErrorPrettified`, `flagErrorPrettified`, `commandHelpText`, etc.)
return `Document`s, keeping output formatting separate from I/O.

## Conventions / gotchas

- This is a **package** (`gren.json` `"type": "package"`): every exposed value
  and type needs a `{-| … -}` doc comment and a matching `@docs` entry in the
  module header, or `gren docs` fails. Keep both in sync when adding/removing
  exports.
- `platform: node` is required *only* by `pathParser` (`FileSystem.Path`).
  Dropping it and the `gren-lang/node` dependency would make the package
  `platform: common` (browser-capable).
- `semanticVersionParser` / `packageNameParser` were intentionally removed from
  the original compiler version to avoid a `gren-lang/compiler-common`
  dependency; re-add them only if building Gren-specific tooling.
- Several features are **intentionally missing** vs. Python `argparse`
  (count/append, mutually-exclusive groups, required options, mixed arity).
  Before "adding a missing feature," check whether the gap is deliberate — many
  have a documented workaround. (Short flags are *not* missing: see `FlagName`'s
  `ShortOnly`/`Both` in the Flags section above.)
