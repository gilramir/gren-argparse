#!/bin/bash

set -e

gren make Main --output=app
node app
