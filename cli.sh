#!/usr/bin/env bash

# -------------------------
# Internal storage
# -------------------------
declare -A CLI_TYPE=()
declare -A CLI_DESC=()
declare -A CLI_ALIAS=()
declare -A CLI_VAR=()        # maps option name → variable name
declare -a CLI_POSITIONAL=()

# -------------------------
# Define option
# -------------------------
# $1: option name (--verbose or -v)
# $2: result variable name
# $3: type (flag | required | optional)
# $4: description
# $5: default value (optional, used only if explicitly set via var)
cli_option() {
  local opt="$1"
  local var="$2"
  local type="$3"
  local desc="$4"
  local default="$5"

  CLI_TYPE["$opt"]="$type"
  CLI_DESC["$opt"]="$desc"
  CLI_VAR["$opt"]="$var"

  # Only assign default if variable is undefined
  if [[ -n "$default" && -z "${!var+x}" ]]; then
    eval "$var=\"\$default\""
  fi
}

# -------------------------
# Define alias
# -------------------------
cli_alias() {
  local alias="$1"
  local target="$2"
  CLI_ALIAS["$alias"]="$target"
}

# -------------------------
# Help generation
# -------------------------
cli_help() {
  echo "Usage: $0 [options] [args]"
  echo
  echo "Options:"
  for opt in "${!CLI_TYPE[@]}"; do
    type="${CLI_TYPE[$opt]}"
    desc="${CLI_DESC[$opt]}"
    
    case "$type" in
      flag) arg="[+/-]" ;;
      required) arg="<arg>" ;;
      optional) arg="[arg]" ;;
    esac
    
    printf "  %-15s %s\n" "$opt$arg" "$desc"
  done
}

# -------------------------
# Internal helpers
# -------------------------
_cli_map_alias() {
  local opt="$1"
  echo "${CLI_ALIAS[$opt]:-$opt}"
}

_cli_is_value() {
  [[ -n "$1" && "$1" != -* && "$1" != +* ]]
}

# -------------------------
# Parse arguments
# -------------------------
cli_parse() {
  while [[ $# -gt 0 ]]; do
    arg="$1"
    val=""
    toggle=""

    case "$arg" in
      --*|++*)
        opt="${arg%%=*}"
        val="${arg#*=}"
        [[ "$opt" == "$val" ]] && val=""
        opt="${opt#--}"
        opt="${opt#++}"
        ;;
      -*|+*)
        opt="${arg:1:1}"
        val="${arg:2}"
        ;;
      --)
        shift
        CLI_POSITIONAL+=("$@")
        break
        ;;
      *)
        CLI_POSITIONAL+=("$arg")
        shift
        continue
        ;;
    esac

    # map alias
    opt="$(_cli_map_alias "$opt")"

    # detect toggle
    case "$opt" in
      *+) toggle="on";  opt="${opt%+}" ;;
      *-) toggle="off"; opt="${opt%-}" ;;
    esac

    type="${CLI_TYPE[$opt]}"
    var="${CLI_VAR[$opt]}"

    if [[ -z "$type" || -z "$var" ]]; then
      echo "❌ Unknown option: $opt" >&2
      exit 1
    fi

    if [[ "$opt" == "help" ]]; then
      cli_help
      exit 0
    fi

    # Only overwrite variable if option is actually passed
    case "$type" in
      flag)
        if [[ -n "$toggle" ]]; then
          [[ "$toggle" == "on" ]] && eval "$var=1" || eval "$var=0"
        else
          eval "$var=1"
        fi
        ;;
      required)
        if [[ -n "$toggle" ]]; then
          echo "❌ Option '$opt' does not support +/- toggle" >&2
          exit 1
        fi
        if [[ -n "$val" ]]; then
          eval "$var=\"\$val\""
        elif _cli_is_value "$2"; then
          eval "$var=\"\$2\""
          shift
        else
          echo "❌ Option '$opt' requires an argument" >&2
          exit 1
        fi
        ;;
      optional)
        if [[ -n "$toggle" ]]; then
          [[ "$toggle" == "on" ]] && eval "$var=1" || eval "$var=0"
        elif [[ -n "$val" ]]; then
          eval "$var=\"\$val\""
        elif _cli_is_value "$2"; then
          eval "$var=\"\$2\""
          shift
        fi
        # if not passed, leave previous value untouched
        ;;
    esac

    shift
  done
}
