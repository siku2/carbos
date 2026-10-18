# shellcheck shell=bash

branch=${1:-$(git rev-parse --abbrev-ref origin/HEAD | cut -d/ -f2-)}

if [ "$(git branch --show-current)" = "$branch" ]; then
  git pull
else
  git fetch origin "$branch:$branch"
fi
