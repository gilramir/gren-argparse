#!/bin/bash

set -e

# The Cli.Program suite (Test.Cli.Program) drives the with-permissions and
# root-with-permissions examples as child processes, so build them first.
( cd ../examples/with-permissions && gren make Main --output=app )
( cd ../examples/root-with-permissions && gren make Main --output=app )

gren make Main --output=app
node app "$@"
