# shellcheck shell=bash

git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads |
  awk '$2 == "[gone]" { print $1 }'
