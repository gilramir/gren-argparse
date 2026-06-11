#!/bin/bash

set -e

# The Cli.Program suite (Test.Cli.Program) drives the with-permissions example
# as a child process, so build that example first.
( cd ../examples/with-permissions && gren make Main --output=app )

gren make Main --output=app
node app "$@"
