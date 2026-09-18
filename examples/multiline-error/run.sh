#!/bin/bash

set -e

geng make Main --output=app
node app "$@"
