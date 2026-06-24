# gren-argparse

Declarative command-line argument parsing for Gren. Describe your CLI as a
value; get back a typed command to pattern-match on.

Built-in `--help`, `--version`, and ANSI-colored error messages are included.

## A quick look

```
% todo add "buy milk" --done
% todo add "buy milk" -d
% todo list
```

The walkthrough below builds this `todo` tool step by step.

## How it works

You describe your CLI as a value, hand it the raw `argv`, and get back a typed
result:

```
Argparse.Parser.run argv app  →  CommandParseResult YourCommand
```

Parsing is a **pure function** — no I/O, no process exits. You get a result
back and decide what to print and what exit code to use.

`Argparse.Program` is an optional wrapper that makes the obvious decisions for
you: errors go to stderr, help goes to stdout, and a successful parse calls your
handler.

## 1. Define your command type

This is your type — the parser's job is to produce it.

```gren
type Command
    = Add { text : String, done : Bool }
    | List
```

## 2. Describe your commands

An `App` ties the tool name, version, and a list of commands together.

```gren
import Argparse.Parser
import Argparse.PrettyPrinter as PP

parser : Argparse.Parser.App Command
parser =
    { name = "todo"
    , version = "1.0.0"
    , intro = PP.words "A small todo list."
    , outro = PP.empty
    , commands =
        Argparse.Parser.defineGroup
            |> Argparse.Parser.withCommand
                { word = "add"
                , arguments =
                    Argparse.Parser.oneArg
                        { value = textParser
                        , help = "The task to add"
                        }
                , flags =
                    Argparse.Parser.initFlags (\done -> { done = done })
                        |> Argparse.Parser.toggle (Argparse.Parser.Both { long = "done", short = "d" }) "Mark it already done"
                , commonDescription = Just "Add a task to the list."
                , summary = "The `add` command appends a task:"
                , example = PP.words "todo add \"buy milk\""
                , builder =
                    \text flags ->
                        Add { text = text, done = flags.done }
                }
            |> Argparse.Parser.withCommand
                { word = "list"
                , arguments = Argparse.Parser.noArgs
                , flags = Argparse.Parser.noFlags
                , commonDescription = Just "Show every task."
                , summary = "The `list` command prints the tasks:"
                , example = PP.words "todo list"
                , builder = \_args _flags -> List
                }
    }
```

You can nest groups under a prefix word with `withPrefix` to get
`git`-style subcommands like `todo remote add origin`.

### Arguments

Each command declares the positional arguments it accepts. Pick the combinator
for the arity you want:

- `noArgs` — no positional arguments
- `oneArg` / `twoArgs` / `threeArgs` — exact arity
- `optionalArg` — zero or one (`Maybe`)
- `zeroOrMoreArgs` — zero or more
- `oneOrMoreArgs` — one or more

### Flags

Flags are type-safe: `initFlags` takes a record constructor, and each
`toggle`/`flag` call fills in one field. The compiler checks that you've wired
everything up correctly.

- `toggle name desc` — a `Bool` (true when the flag is present)
- `flag name valueParser desc` — a `Maybe value`

A flag's name controls which spellings the user can type:

- `LongOnly "verbose"` → `--verbose`
- `ShortOnly "v"` → `-v`
- `Both { long = "verbose", short = "v" }` → `--verbose` or `-v`

`--help` (and `-h`) and `--version` are always available — you don't need to
declare them.

### ValueParser

A `ValueParser` converts a raw string into a typed value. Write your own in a
few lines:

```gren
textParser : Argparse.Parser.ValueParser String
textParser =
    { label = "text", fn = Just, examples = [ "buy milk" ] }
```

Built-in: `pathParser`.

## 3. Run it

`Argparse.Program.run` wires the parser into a `Node` program:

```gren
import Argparse.Program
import Node
import Stream.Log
import Task

main : Node.SimpleProgram a
main =
    Argparse.Program.run
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
                    |> Task.map (\_ -> Argparse.Program.Succeeded)
        }
```

`onCommand` receives the `Node.Environment` (stdout, stderr, args, …) and your
parsed command.

## Exit codes

Your handler returns a `Task String Argparse.Program.Outcome`. There are three
outcomes:

| Return | Exit | When |
| --- | --- | --- |
| `Task.succeed Succeeded` | `0` | the command did its job |
| `Task.succeed Failed` | `1` | it ran fine, but the answer is "no" — you've already printed your report |
| `Task.fail "message"` | `1` | something went wrong; the message is printed to stderr |

The `Failed` / `Task.fail` split maps to how Unix tools actually behave.
`grep` exits `1` for "no matches" and `2` for "invalid regex" — those are
different situations. A linter that found problems should return `Failed` (the
problems are the expected output, not a crash).

If your command always succeeds, just end with:

```gren
|> Task.map (\_ -> Argparse.Program.Succeeded)
```

> Need a different exit code, like `2`? See `examples/manual/`, which calls
> `Argparse.Parser.run` directly and handles the result itself.

## Choosing a runner

`Argparse.Program` has four entry points:

- **`run`** — the standard case: an `App` with one or more subcommands.
- **`runRoot`** — no subcommand word; the whole tool is one command
  (like `greet --loud World`). You pass a single `Command` instead of an `App`.
- **`runWithContext`** — like `run`, but runs an `Init.await` chain first so
  you can acquire permissions (`FileSystem`, terminal, …) before any command runs.
- **`runRootWithContext`** — `runRoot` plus the up-front permission acquisition.

## Examples

Each example in `examples/` is a self-contained app with a `run.sh`:

| Directory | What it shows |
| --- | --- |
| `no-subcommand/` | `runRoot` — no command word |
| `one-level/` | `run` + `withCommand` |
| `two-level/` | `withPrefix` — nested subcommands |
| `manual/` | `Argparse.Parser.run` directly, custom exit code |
| `with-permissions/` | `runWithContext` — acquiring a `FileSystem.Permission` |
| `root-with-permissions/` | `runRootWithContext` — rootless tool with permissions |

```bash
cd examples/one-level
./run.sh add "buy milk"
./run.sh --help
```

## Testing

The parser is pure, so you can test it directly with `gren-lang/test`:

```bash
cd tests
./run-tests.sh
```
