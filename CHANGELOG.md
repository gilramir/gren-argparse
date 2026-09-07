# Changelog

## [2.0.1] - 2026-09-07

### Changed

- Wrap help and error output to the width of the terminal, falling back to 80
  columns when there is no terminal to ask

### Added

- Document how wrapping works, with worked examples, in the
  `Argparse.PrettyPrinter` module documentation and the README

### Fixed

- Wrap a `block` part against the columns its neighbors to the left already
  took, instead of against the full width as if it started at column 0
- Open a wrapped line with the indent it belongs under, which `block` parts
  after the first and split `text` were missing
- Count the space between two words when wrapping, which could leave a `words`
  line one column wider than `maxColumns`

## [2.0.0] - 2026-07-17

### Changed

- **Breaking:** add `FlagParserMissingRequiredFlag` to `FlagParserError`, which
  exhaustive `when` expressions over that type must now handle

### Added

- Add `requiredFlag`, a value flag that must be provided: it fills its
  constructor argument with `value` rather than `Maybe value`, fails the parse
  when absent, and is annotated `(required)` in `--help`

## [1.0.1] - 2026-07-01

### Changed

- Strip ANSI color from help and error output when stdout is not a terminal or
  `NO_COLOR` is set

## [1.0.0] - 2026-06-25

_First release._

[2.0.1]: https://github.com/gilramir/gren-argparse/releases/tag/2.0.1
[2.0.0]: https://github.com/gilramir/gren-argparse/releases/tag/2.0.0
[1.0.1]: https://github.com/gilramir/gren-argparse/releases/tag/1.0.1
[1.0.0]: https://github.com/gilramir/gren-argparse/releases/tag/1.0.0
