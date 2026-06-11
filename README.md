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

## How it works

You never write imperative parsing. You describe an `App`, run it over the
arguments, and pattern-match the result:

```
argv ──▶ Cli.Parser.run argv app ──▶ CommandParseResult YourCommand ──▶ you dispatch
```

`run` handles `--help`, `--version`, the bare-invocation help screen, unknown
commands, missing/invalid flags and arguments — each as a constructor of
`CommandParseResult`.

## Defining commands

An `App` is a record with a tree of commands built by folding combinators:

```gren
Cli.Parser.defineGroup
    |> Cli.Parser.withCommand { word = "greet", arguments = …, flags = …, builder = … }
    |> Cli.Parser.withPrefix "package" packageSubcommands   -- nested: `mytool package …`
```

Each command declares:

- **arguments** — `noArgs`, `oneArg`, `twoArgs`, `threeArgs`, `optionalArg`
  (zero-or-one → `Maybe`), `zeroOrMoreArgs` (`*`), `oneOrMoreArgs` (`+`),
  combined with `mapArgs` / `oneOfArgs`. Each positional takes an
  `Arg { value, help }` (a `ValueParser` plus per-argument help text).
- **flags** — `initFlags` seeds a record constructor; `toggle` adds a `Bool`
  flag, `flag` adds a `Maybe value` flag. They assemble your flags record
  type-safely as you chain them.
- **builder** — `args -> flags -> YourCommand`, the bridge from parsed input to
  your own command value.

A `ValueParser` is just a record — define your own in a few lines:

```gren
nameParser : Cli.Parser.ValueParser String
nameParser =
    { singular = "name", plural = "names", fn = Just, examples = [ "World" ] }
```

Built-in value parsers: `pathParser`, `grenFileParser`.

## Running it

A few options, in increasing order of control:

**`Cli.Program.run` (convenient).** Hands you only the success case; parse
errors go to stderr with exit `1`, help goes to stdout:

```gren
main : Node.SimpleProgram a
main =
    Cli.Program.run
        { parser = MyCli.parser
        , onCommand =
            \env command ->
                when command is
                    MyCli.Greet { name } ->
                        Stream.Log.line env.stdout ("Hello, " ++ name)
        }
```

`onCommand` returns a `Task String {}`; if it fails, the `String` is printed to
stderr and the program exits `1` — the same treatment parse errors get. See
`examples/one-level/`.

**`Cli.Program.runRoot` (no sub-commands).** For a tool that is just flags and
arguments, with no command word — `mytool --loud World`. You give it a single
`Command` instead of an `App`; everything else (errors, `--help`, `--version`,
exit codes) works like `run`. See `examples/no-subcommand/`.

**`Cli.Program.runWithContext` (run + permissions).** Like `run`, but with a
chance to initialize subsystems and acquire permissions
(`FileSystem.Permission`, terminal, child processes, …) before any command
runs — these can only be obtained in a program's initialization phase, which
`run` doesn't expose. Your `init` is handed the environment and a continuation;
`Init.await` whatever you need, then call the continuation with a *context*
value that is passed to every `onCommand`. See `examples/with-permissions/`.

**`Cli.Parser.run` (full control).** Call the pure parser yourself and handle
each `CommandParseResult` constructor by hand (the `argv → result → dispatch`
flow above) — use this when you need a custom exit code or your own
model/update loop. See `examples/manual/`.

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
| `with-permissions/` | `Cli.Program.runWithContext` — a `FileSystem.Permission` | `./run.sh count gren.json` |

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

## Notes

- `platform: node` is required only by `pathParser` / `grenFileParser`
  (`FileSystem.Path`). Drop those two parsers and the `gren-lang/node`
  dependency to get a `platform: common` (browser-capable) package.
- The original also shipped `semanticVersionParser` and `packageNameParser`
  (pulling in `gren-lang/compiler-common`). They were removed here to keep the
  package general-purpose; re-add them if you're building Gren tooling.
