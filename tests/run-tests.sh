#!/bin/bash

set -e

# The Cli.Program suite (Test.Cli.Program) drives the with-permissions and
# root-with-permissions examples as child processes, so build them first.
echo Compiling ../examples/with-permissions
( cd ../examples/with-permissions && gren make Main --output=app )

echo Compiling ../examples/root-with-permissions
( cd ../examples/root-with-permissions && gren make Main --output=app )

echo Compiling ../examples/multiline-error
( cd ../examples/multiline-error && gren make Main --output=app )

echo Compiling the tests
gren make Main --output=app

echo Running the tests
node app "$@"
