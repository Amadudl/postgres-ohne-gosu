#!/bin/sh
# Projektpruefungen fuer den pre-commit Hook (postgres-ohne-gosu): Shell Syntax.
set -e
cd "$(git rev-parse --show-toplevel)"
sh -n test.sh
