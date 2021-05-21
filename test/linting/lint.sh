#! /bin/bash

# version   v0.1.3 stable
# executed  by CI / manually (via Make)
# task      checks files agains linting targets

SCRIPT="lint.sh"

# macOS doesn't support readlink -f, so work around it
if [[ "$(uname -s)" == "Darwin" ]]; then
  function readlink() {
    [[ "$1" == "-f" ]] && shift
    DIR="${1%/*}"
    (cd "$DIR" && echo "$(pwd -P)")
  }
  function realpath() {
    local OURCDIR=$CDIR
    cd "$(dirname "$1")"
    local LINK=$(readlink "$(basename "$1")")
    while [ "$LINK" ]; do
      cd "$(dirname "$LINK")"
      local LINK=$(readlink "$(basename "$1")")
    done
    local REALPATH="$CDIR/$(basename "$1")"
    cd "$OURCDIR"
    echo "$REALPATH"
  }
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ? ––––––––––––––––––––––––––––––––––––––––––––– ERRORS

set -eEuo pipefail
trap '__log_err ${FUNCNAME[0]:-"?"} ${BASH_COMMAND:-"?"} ${LINENO:-"?"} ${?:-"?"}' ERR

function __log_err
{
  printf "\n––– \e[1m\e[31mUNCHECKED ERROR\e[0m\n%s\n%s\n%s\n%s\n\n" \
    "  – script    = ${SCRIPT:-${0}}" \
    "  – function  = ${1} / ${2}" \
    "  – line      = ${3}" \
    "  – exit code = ${4}"

  unset CDIR SCRIPT OS VERSION
}

# ? ––––––––––––––––––––––––––––––––––––––––––––– LOG

function __log_info
{
  printf "\n––– \e[34m%s\e[0m\n%s\n%s\n\n" \
    "${SCRIPT:-${0}}" \
    "  – type    = INFO" \
    "  – message = ${*}"
}

function __log_failure
{
  printf "\n––– \e[91m%s\e[0m\n%s\n%s\n\n" \
    "${SCRIPT:-${0}}" \
    "  – type    = FAILURE" \
    "  – message = ${*:-'errors encountered'}"
}

function __log_success
{
  printf "\n––– \e[32m%s\e[0m\n%s\n%s\n\n" \
    "${SCRIPT}" \
    "  – type    = SUCCESS" \
    "  – message = no errors detected"
}

function __in_path { __which "${@}" && return 0 ; return 1 ; }
function __which { command -v "${@}" &>/dev/null ; }

function _eclint
{
  local SCRIPT='EDITORCONFIG LINTER'
  local LINT=(eclint -exclude "(.*\.git.*|.*\.md$|\.bats$|\.cf$|\.conf$|\.init$)")

  if ! __in_path "${LINT[0]}"
  then
    __log_failure 'linter not in PATH'
    return 2
  fi

  __log_info 'linter version:' "$(${LINT[0]} --version)"

  if "${LINT[@]}"
  then
    __log_success
  else
    __log_failure
    return 1
  fi
}

function _hadolint
{
  local SCRIPT='HADOLINT'
  local LINT=(hadolint -c "${CDIR}/.hadolint.yaml")

  if ! __in_path "${LINT[0]}"
  then
    __log_failure 'linter not in PATH'
    return 2
  fi

  __log_info 'linter version:' \
    "$(${LINT[0]} --version | grep -E -o "[0-9\.].*")"

  if git ls-files --exclude='Dockerfile*' --ignored | \
    xargs -L 1 "${LINT[@]}"
  then
    __log_success
  else
    __log_failure
    return 1
  fi
}

function _shellcheck
{
  local SCRIPT='SHELLCHECK'
  local ERR=0
  local LINT=(shellcheck -x -S style -Cauto -o all -e SC2154 -W 50)

  if ! __in_path "${LINT[0]}"
  then
    __log_failure 'linter not in PATH'
    return 2
  fi

  __log_info 'linter version:' \
    "$(${LINT[0]} --version | grep -m 1 -o "[0-9.].*")"

  # an overengineered solution to allow shellcheck -x to
  # properly follow `source=<SOURCE FILE>` when sourcing
  # files with `. <FILE>` in shell scripts.

  find . -type f -iname "*.sh" \
    -not -path "./test/bats/*" \
    -not -path "./test/test_helper/*" \
    -not -path "./target/docker-configomat/*"

  while read -r FILE
  do
    readlink -f "${FILE}"
    dirname "$(readlink -f "${FILE}")"
    realpath "$(dirname "$(readlink -f "${FILE}")")"
    echo "$(realpath "$(dirname "$(readlink -f "${FILE}")")")"

    if ! (
      cd "$(realpath "$(dirname "$(readlink -f "${FILE}")")")"
      if ! "${LINT[@]}" "$(basename -- "${FILE}")"
      then
        exit 1
      fi
    )
    then
      ERR=1
    fi
  done < <(find . -type f -iname "*.sh" \
    -not -path "./test/bats/*" \
    -not -path "./test/test_helper/*" \
    -not -path "./target/docker-configomat/*")

  # the same for executables in target/bin/
  while read -r FILE
  do
    if ! (
      cd "$(realpath "$(dirname "$(readlink -f "${FILE}")")")"
      if ! "${LINT[@]}" "$(basename -- "${FILE}")"
      then
        exit 1
      fi
    )
    then
      ERR=1
    fi
  done < <(find target/bin -executable -type f)

  # the same for all test files
  while read -r FILE
  do
    if ! (
      cd "$(realpath "$(dirname "$(readlink -f "${FILE}")")")"
      if ! "${LINT[@]}" "$(basename -- "${FILE}")"
      then
        exit 1
      fi
    )
    then
      ERR=1
    fi
  done < <(find test/ -maxdepth 1 -type f -iname "*.bats")

  if [[ ${ERR} -eq 1 ]]
  then
    __log_failure 'errors encountered'
    return 1
  else
    __log_success
  fi
}

function _main
{
  case ${1:-} in
    'eclint'      ) _eclint     ;;
    'hadolint'    ) _hadolint   ;;
    'shellcheck'  ) _shellcheck ;;
    *)
      __log_failure \
        "${SCRIPT}: '${1}' is not a command nor an option."
      exit 3
      ;;
  esac
}

# prefer linters installed in tools
PATH="$(pwd)/tools:${PATH}"
export PATH

_main "${@}" || exit ${?}
