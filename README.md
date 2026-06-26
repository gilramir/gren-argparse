# gren-argparse

Declarative command-line argument parsing for Gren. Describe your CLI as a
value; get back a typed command to pattern-match on.  A `Program` package
is also included, providing common functionality for a CLI program for
parsing a command-line, running code, and exiting with a proper return code.

Built-in `--help`, `--version`, and ANSI-colored error messages are included.

## Example of what is supported

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

`Argparse.Program` is an optional wrapper that handles the bootstrapping for
you: CLI errors go to stderr, help goes to stdout, and a successful parse calls your
handler. Then your handler tells `Program` which return code the process should
exit with.

## 1. Define your program's options type

This is your type; the parser's job is to produce it.

```gren
type ProgramOptions
    = Add { text : String, done : Bool }
    | List
```

## 2. Describe your commands

An `App` ties the tool name, version, and a list of commands together.

```gren
import Argparse.Parser
import Argparse.PrettyPrinter as PP

parser : Argparse.Parser.App ProgramOptions
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
                        { value = Argparse.Parser.stringParser
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

Note: You can nest groups under a prefix word with `withPrefix` to get
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

A `ValueParser` converts a raw string into a typed value. Two are built in:
`stringParser` (any `String`) and `pathParser` (`FileSystem.Path`). Write your
own in a few lines:

```gren
myParser : Argparse.Parser.ValueParser MyType
myParser =
    { label = "mytype", fn = MyType.fromString, examples = [ "example" ] }
```

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
                    |> Task.map (\_ -> {})
        }
```

`onCommand` receives the `Node.Environment` (stdout, stderr, args, …) and your
parsed command.

## Exit codes

Your handler returns a `Task Argparse.Program.Failure {}`. `Task.succeed {}` is
the only exit-0 path; all non-zero exits go through `Task.fail`:

| Return | Exit | Behavior |
| --- | --- | --- |
| `Task.succeed {}` | `0` | command succeeded |
| `Task.fail ExitFailure` | `1` | silent exit 1 (you already printed your report) |
| `Task.fail (ExitMessage "msg")` | `1` | print `msg` to stderr, then exit 1 |
| `Task.fail (ExitValue n)` | `n` | exit with code `n`, print nothing |
| `Task.fail (ExitMessageValue { message = "msg", value = n })` | `n` | print `msg` to stderr, then exit `n` |

If your command always succeeds, just end with:

```gren
|> Task.map (\_ -> {})
```

Need a full model/update loop? Call `Argparse.Parser.run` directly and handle
each constructor yourself:

```gren
main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        let
            args =
                Array.dropFirst 2 env.args
        in
        Node.endSimpleProgram <|
            when Argparse.Parser.run args parser is
                Argparse.Parser.UnknownCommand name ->
                    Stream.Log.line env.stderr ("Unknown command: " ++ name)
                        |> Task.andThen (\_ -> Node.setExitCode 1)

                Argparse.Parser.BadFlags err ->
                    Stream.Log.line env.stderr (PP.toString (Argparse.Parser.flagErrorPrettified err))
                        |> Task.andThen (\_ -> Node.setExitCode 1)

                Argparse.Parser.BadArguments err ->
                    Stream.Log.line env.stderr (PP.toString (Argparse.Parser.argumentErrorPrettified err))
                        |> Task.andThen (\_ -> Node.setExitCode 1)

                Argparse.Parser.HelpText doc ->
                    Stream.Log.line env.stdout (PP.toString doc)

                Argparse.Parser.Success cmd ->
                    runCommand env cmd
```

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

If you use devbox, you can build all examlpes with:
```bash
devbox run examples
```

## Testing

The parser is pure, so you can test it directly with `gren-lang/test`:

```bash
cd tests
./run-tests.sh
```

If you use devbox, just run:
```bash
devbox run test
```
