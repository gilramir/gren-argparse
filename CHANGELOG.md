# Changelog

## 2.0.0

- Wrap help and error output to the terminal's width, falling back to 80
  columns when there's no terminal attached (output redirected to a pipe or a
  file). A reported width narrower than 20 columns is ignored in favor of the
  fallback.
- Fix an off-by-one in `Argparse.PrettyPrinter`'s word wrapping: the space
  joining two words wasn't counted, so a `words` line could come out one
  column wider than `maxColumns`.
- Add `requiredFlag`: a value flag that must be provided. It fills its
  constructor argument directly (`value`, not `Maybe value`) and fails the parse
  with the new `FlagParserMissingRequiredFlag` error if absent. Required flags
  are annotated `(required)` in `--help`.

## 1.0.1

- Don't colorize the help output if stdout isn't connected to a TTY

## 1.0.0

- First release
