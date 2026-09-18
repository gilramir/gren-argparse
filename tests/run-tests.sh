#!/bin/bash

set -e

# The Cli.Program suite (Test.Cli.Program) drives the with-permissions and
# root-with-permissions examples as child processes, so build them first.
for example in with-permissions root-with-permissions multiline-error; do
  echo Compiling ../examples/$example
  ( cd ../examples/$example && geng make Main --output=app )
done

echo Compiling the tests
geng make Main --output=app

echo Running the tests
node app "$@"
