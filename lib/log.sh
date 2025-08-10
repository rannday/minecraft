# shellcheck shell=bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run.">&2; exit 1; }

log_ts() { date +"[%Y-%m-%d %H:%M:%S]"; }

info()  { printf '%s \e[32m[INFO]\e[0m %s\n'  "$(log_ts)" "$@" >&2; }
warn()  { printf '%s \e[33m[WARN]\e[0m %s\n'  "$(log_ts)" "$@" >&2; }
error() { printf '%s \e[31m[ERROR]\e[0m %s\n' "$(log_ts)" "$@" >&2; }
fatal() { printf '%s \e[31m[FATAL]\e[0m %s\n' "$(log_ts)" "$@" >&2; exit 1; }