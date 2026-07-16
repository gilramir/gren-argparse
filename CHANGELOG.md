# Changelog

## Unreleased

- Add `requiredFlag`: a value flag that must be provided. It fills its
  constructor argument directly (`value`, not `Maybe value`) and fails the parse
  with the new `FlagParserMissingRequiredFlag` error if absent. Required flags
  are annotated `(required)` in `--help`.

## 1.0.1

- Don't colorize the help output if stdout isn't connected to a TTY

## 1.0.0

- First release
