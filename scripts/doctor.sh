#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DEV_BOOTSTRAP_TEST=1
export MAC_DEV_BOOTSTRAP_TEST

# shellcheck source=../install.sh
source "${ROOT_DIR}/install.sh"
main --doctor "$@"
