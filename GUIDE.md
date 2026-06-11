# Programmer's guide

A walkthrough of building a command-line tool with `gren-cli`, from an empty
`Main.gren` to a program that parses arguments, prints help, and reports the
right exit code. If you just want the API surface, the module docs (`gren docs`)
and the [README](README.md) are the reference; this is the narrative version.

The running example is a tiny todo tool, `todo`, with two commands:

```
todo add "buy milk" --done
todo list
```

## The mental model

You never write imperative argument parsing. You **describe** your CLI as a
value, hand it the raw arguments, and get back a value of *your own* command
type to pattern-match on:

```
argv ──▶ Cli.Parser.run argv app ──▶ CommandParseResult YourCommand ──▶ you dispatch
```

Parsing is a pure function: it does no I/O and never exits the process. That
purity is the whole point — it makes the parser testable and lets *you* decide
what to print and which exit code to use. `Cli.Program` is an opinionated
wrapper that makes those decisions for you so you don't have to.

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

A `Command` (the library's) ties together arguments, flags, help text, and a
`builder` that bridges parsed input into your `Command` type above.

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

A few things worth knowing:

- **Arguments** consume the whole positional array at once. Pick the combinator
  for the arity you want: `noArgs`, `oneArg`/`twoArgs`/`threeArgs` (exact),
  `optionalArg` (`?` → `Maybe`), `zeroOrMoreArgs` (`*`), `oneOrMoreArgs` (`+`),
  with `mapArgs`/`oneOfArgs` for variations. (There's no "one required then
  variadic rest" — some gaps are deliberate.)
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
      { singular = "text", plural = "texts", fn = Just, examples = [ "buy milk" ] }
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
  of an `App`. (`examples/no-subcommand/`.)
- **`runWithContext`** — like `run`, but it lets you run your own `Init.await`
  chain first to acquire permissions (`FileSystem`, terminal, child processes),
  then threads the resulting *context* into every handler. Use it whenever a
  command needs to touch a subsystem. (`examples/with-permissions/`.)

If you need something these don't give you — a custom exit code, a full
model/update loop — skip `Cli.Program` and call `Cli.Parser.run` directly,
matching on its five-constructor `CommandParseResult` by hand
(`examples/manual/`).

## Trying the examples

Every scenario above is a self-contained app under `examples/`, each with a
`run.sh` that builds and runs it:

```bash
cd examples/one-level
./run.sh add "buy milk"
./run.sh --help
```

## Testing

The parser is pure, so test it directly with `gren-lang/test`: feed
`Cli.Parser.run` an argument array and assert on the `CommandParseResult`. See
`tests/src/Test/Cli/Parser.gren`, run with `tests/run-tests.sh`.

The exit-code behavior of `Cli.Program` is I/O, so it's covered by a small
integration script, `tests/exit-codes.sh`, which runs the `with-permissions`
example and asserts the exit code and stream for each `Outcome`.
