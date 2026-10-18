# shellcheck shell=bash

git fetch --prune
list-dead-branches | while read -r branch; do
  git branch -D "$branch"
done
