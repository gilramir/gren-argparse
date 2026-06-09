# gren-cli

Declarative command-line argument parsing for Gren, with built-in `--help`,
`--version`, and prettified error messages.

Extracted from the Gren compiler's CLI (`gren init`, `gren make`, …). Two
modules:

- **`Cli.Parser`** — turn `argv` into a value of your own command type.
- **`Cli.PrettyPrinter`** — the ANSI-color-aware document type used for help
  and error output (`PP.text`, `PP.words`, `PP.block`, `PP.color`, …).

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
