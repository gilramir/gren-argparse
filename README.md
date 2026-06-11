# gren-cli

Declarative command-line argument parsing for Gren, with built-in `--help`,
`--version`, and prettified error messages.

Extracted from the Gren compiler's CLI (`gren init`, `gren make`, …). Three
modules:

- **`Cli.Parser`** — turn `argv` into a value of your own command type. Pure;
  no I/O.
- **`Cli.PrettyPrinter`** — the ANSI-color-aware document type used for help
  and error output (`PP.text`, `PP.words`, `PP.block`, `PP.color`, …).
- **`Cli.Program`** — an optional convenience runner that wires `Cli.Parser`
  into a `Node` program, printing parse errors to stderr and exiting `1`,
  printing help to stdout, and handing successful commands to you.

The sections below double as a walkthrough: a tiny todo tool, `todo`, built up
from its command type to a program that parses arguments, prints help, and
reports the right exit code.

```
todo add "buy milk" --done
todo list
```

If you just want the API surface, the module docs (`gren docs`) are the
reference.

## How it works

You never write imperative argument parsing. You **describe** your CLI as a
value, hand it the raw arguments, and get back a value of *your own* command
type to pattern-match on:

```
argv ──▶ Cli.Parser.run argv app ──▶ CommandParseResult YourCommand ──▶ you dispatch
```

Parsing is a pure function: it does no I/O and never exits the process. That
purity is the whole point — it makes the parser testable and lets *you* decide
what to print and which exit code to use. `run` handles `--help`, `--version`,
the bare-invocation help screen, unknown commands, and missing/invalid flags
and arguments — each as a constructor of `CommandParseResult`. `Cli.Program` is
an opinionated wrapper that makes those decisions for you so you don't have to.

There are three layers, which you compose:

1. **Commands** — the words a user types (`add`, `list`, `remote add`).
2. **Arguments** — the positional values after the command (`"buy milk"`).
3. **Flags** — the `--long` options (`--done`).

## 1. Your command type

Start from the type you actually want to handle. This is *your* type, not the
library's — the parser's job is to produce it.

```gren
type Command
    = Add { text : String, done : Bool }
    | List
```

## 2. Describe each command

An `App` is a record with a tree of commands built by folding combinators. Each
library `Command` ties together arguments, flags, help text, and a `builder`
that bridges parsed input into your `Command` type above.

```gren
import Cli.Parser
import Cli.PrettyPrinter as PP

parser : Cli.Parser.App Command
parser =
    { name = "todo"
    , version = "1.0.0"
    , intro = PP.words "A small todo list."
    , outro = PP.empty
    , commands =
        Cli.Parser.defineGroup
            |> Cli.Parser.withCommand
                { word = "add"
                , arguments =
                    Cli.Parser.oneArg
                        { value = textParser
                        , help = "The task to add"
                        }
                , flags =
                    Cli.Parser.initFlags (\done -> { done = done })
                        |> Cli.Parser.toggle "done" "Mark it already done"
                , commonDescription = Just "Add a task to the list."
                , summary = "The `add` command appends a task:"
                , example = PP.words "todo add \"buy milk\""
                , builder =
                    \text flags ->
                        Add { text = text, done = flags.done }
                }
            |> Cli.Parser.withCommand
                { word = "list"
                , arguments = Cli.Parser.noArgs
                , flags = Cli.Parser.noFlags
                , commonDescription = Just "Show every task."
                , summary = "The `list` command prints the tasks:"
                , example = PP.words "todo list"
                , builder = \_args _flags -> List
                }
    }
```

You can also nest a whole group under a prefix word with `withPrefix`, giving
`git`/`click`-style subcommand trees (`todo remote add origin`).

A few things worth knowing:

- **Arguments** consume the whole positional array at once. Pick the combinator
  for the arity you want: `noArgs`, `oneArg`/`twoArgs`/`threeArgs` (exact),
  `optionalArg` (`?` → `Maybe`), `zeroOrMoreArgs` (`*`), `oneOrMoreArgs` (`+`),
  with `mapArgs`/`oneOfArgs` for variations. (There's no "one required then
  variadic rest" — some gaps are deliberate.) Each positional takes an
  `Arg { value, help }` (a `ValueParser` plus per-argument help text).
- **Flags** are built type-safely. `initFlags` seeds a record constructor;
  `toggle` adds a `Bool`, `flag` adds a `Maybe value`. Each chained combinator
  fills one constructor argument, so the flags record is compiler-checked. Only
  `--long` flags exist; there are no short flags, and value flags are always
  optional.
- A **`ValueParser`** is the unit of type conversion, shared by arguments and
  value flags. It's just a record — write your own in a few lines:

  ```gren
  textParser : Cli.Parser.ValueParser String
  textParser =
      { label = "text", fn = Just, examples = [ "buy milk" ] }
  ```

  Built-ins: `pathParser`, `grenFileParser`.

`--help` and `--version` are handled for you; you don't declare them.

## 3. Run it

For most tools, `Cli.Program.run` is all you need. It wires the parser into a
`Node` program and makes the obvious decisions: parse errors → stderr + exit
`1`, `--help`/`--version` → stdout, a parsed command → your handler.

```gren
import Cli.Program
import Node
import Stream.Log
import Task

main : Node.SimpleProgram a
main =
    Cli.Program.run
        { parser = parser
        , onCommand =
            \env cmd ->
                (when cmd is
                    Add { text, done } ->
                        Stream.Log.line env.stdout
                            ((if done then "Added (done): " else "Added: ") ++ text)

                    List ->
                        Stream.Log.line env.stdout "(no tasks yet)"
                )
                    |> Task.map (\_ -> Cli.Program.Succeeded)
        }
```

`onCommand` gets the `Node.Environment` (stdout, stderr, args, …) and your
parsed command. That's it — you've got a working CLI.

## Exit codes: the `Outcome` contract

Your handler returns a `Task String Cli.Program.Outcome`, and `Cli.Program`
turns that into the process exit status. **You never call `Node.setExitCode`.**

There are three results, and the split matches how Unix tools actually behave:

| You return | Exit | When |
| --- | --- | --- |
| `Task.succeed Succeeded` | `0` | the command did its job |
| `Task.succeed Failed` | `1` | it *ran fine, but the answer is no* — a check that didn't pass, a search with no matches, a build with errors. Exits `1` **silently**; you've already printed whatever report you wanted. |
| `Task.fail "message"` | `1` | something went *wrong* and you have a diagnostic to show. The string is printed to **stderr**. |

The distinction between the last two is the useful part. Compare `grep`: it
exits `1` when it simply found no matches (that's `Failed`), but exits `2` and
prints to stderr when the regex was malformed (that's a failed task). A linter
exits `1` because it *found problems* — the problems are the expected output,
not an error — so it returns `Failed` after printing them.

Here's a check command using both failure modes:

```gren
\env cmd ->
    when cmd is
        Lint { path } ->
            readAndLint env.fs path
                -- couldn't even read the file: a real error -> stderr, exit 1
                |> Task.mapError FileSystem.errorToString
                |> Task.andThen
                    (\problems ->
                        if Array.length problems == 0 then
                            Stream.Log.line env.stdout "No problems found."
                                |> Task.map (\_ -> Cli.Program.Succeeded)

                        else
                            -- ran fine, but the answer is "no" -> exit 1, no
                            -- extra diagnostic (we just printed the report)
                            reportProblems env.stderr problems
                                |> Task.map (\_ -> Cli.Program.Failed)
                    )
```

If your handler always succeeds (the common case), the only ceremony is a
trailing `|> Task.map (\_ -> Cli.Program.Succeeded)`.

> Need a *different* code, like `2`? `Cli.Program` is deliberately limited to
> `0`/`1`. Drop down to `Cli.Parser.run` (below) and match on the result
> yourself — see `examples/manual/`, which exits `2` on a parse error.

## Choosing a runner

`Cli.Program` offers three entry points; reach for the lowest-ceremony one that
fits.

- **`run`** — the standard case: an `App` with one or more command words.
  (`examples/one-level/`, `examples/two-level/`.)
- **`runRoot`** — no command word at all, for a tool that is just flags and
  arguments, like `greet --loud World`. You give it a single `Command` instead
  of an `App`; everything else (errors, `--help`, `--version`, exit codes)
  works like `run`. (`examples/no-subcommand/`.)
- **`runWithContext`** — like `run`, but it lets you run your own `Init.await`
  chain first to acquire permissions (`FileSystem.Permission`, terminal, child
  processes, …) before any command runs — these can only be obtained in a
  program's initialization phase, which `run` doesn't expose. Your `init` is
  handed the environment and a continuation; `Init.await` whatever you need,
  then call the continuation with a *context* value that is passed to every
  `onCommand`. (`examples/with-permissions/`.)

If you need something these don't give you — a custom exit code, a full
model/update loop — skip `Cli.Program` and call `Cli.Parser.run` directly,
matching on its five-constructor `CommandParseResult` (`UnknownCommand`,
`BadFlags`, `BadArguments`, `HelpText`, `Success a`) by hand
(`examples/manual/`).

## Examples

The `examples/` directory holds one self-contained app per scenario. Each has a
`run.sh` that builds the program and forwards your arguments to it, so you can
try any example with `./run.sh <args>`:

| Directory | Demonstrates | Try |
| --- | --- | --- |
| `no-subcommand/` | `Cli.Program.runRoot` — flags and args, no command word | `./run.sh --loud World` |
| `one-level/` | `Cli.Program.run` + `withCommand` | `./run.sh add "buy milk"` |
| `two-level/` | `withPrefix` — nested sub-commands | `./run.sh remote add origin` |
| `manual/` | `Cli.Parser.run` by hand, with a custom exit code | `./run.sh greet World --loud` |
| `with-permissions/` | `runWithContext` — a `FileSystem.Permission`, plus all three exit outcomes | `./run.sh count gren.json` |

```bash
cd examples/one-level
./run.sh add "buy milk"
./run.sh --help
```

> Each `run.sh` builds with `gren make Main --output=app` — note the **module
> name** `Main`, not the file path `src/Main.gren` (gren 0.6.5 rejects the path
> form with a `<module-names>` error), and an **executable** `app`, not
> `app.js` (a `.js` output is a *library module* that exports `Main.init`
> without calling it, so it runs and prints nothing).

## Testing

The parser is pure, so test it directly with `gren-lang/test`: feed
`Cli.Parser.run` an argument array and assert on the `CommandParseResult`. See
`tests/src/Test/Cli/Parser.gren`, run with `tests/run-tests.sh`.

The exit-code behavior of `Cli.Program` is I/O, so it's covered by
`Test.Cli.Program`, which uses `blaix/gren-effectful-tests` to drive the built
`with-permissions` example as a child process (`ChildProcess.run`) and asserts
the exit code and stream for each `Outcome` path.

## Notes

- `platform: node` is required only by `pathParser` / `grenFileParser`
  (`FileSystem.Path`). Drop those two parsers and the `gren-lang/node`
  dependency to get a `platform: common` (browser-capable) package.
- The original also shipped `semanticVersionParser` and `packageNameParser`
  (pulling in `gren-lang/compiler-common`). They were removed here to keep the
  package general-purpose; re-add them if you're building Gren tooling.
