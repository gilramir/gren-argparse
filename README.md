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

- **arguments** — `noArgs`, `oneArg`, `twoArgs`, `threeArgs`, `zeroOrMoreArgs`,
  combined with `mapArgs` / `oneOfArgs`. Each takes a `ValueParser`.
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

You have two options.

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
`example/src/Main.gren`.

**`Cli.Parser.run` (full control).** Call the pure parser yourself and handle
each `CommandParseResult` constructor by hand (the `argv → result → dispatch`
flow above) — use this when you need a custom exit code, filesystem/other
permissions, or your own model/update loop. See `example/src/MainManual.gren`.

## Example

See `example/`. Build it as an **executable** and run it:

```bash
cd example
gren make src/Main.gren --output=app   # NOT --output=app.js
node app greet World --loud      # HELLO, WORLD!
node app greet World             # Hello, World.
node app --help
node app greet --help
node app --version
```

> Build with `--output=app` (an executable), not `--output=app.js`. A `.js`
> output is a *library module* that exports `Main.init` without calling it, so
> it runs and prints nothing. The executable output appends the bootstrap that
> actually starts the program. (`./app` works too once it's marked executable.)

## Notes

- `platform: node` is required only by `pathParser` / `grenFileParser`
  (`FileSystem.Path`). Drop those two parsers and the `gren-lang/node`
  dependency to get a `platform: common` (browser-capable) package.
- The original also shipped `semanticVersionParser` and `packageNameParser`
  (pulling in `gren-lang/compiler-common`). They were removed here to keep the
  package general-purpose; re-add them if you're building Gren tooling.
