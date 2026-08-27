#!/usr/bin/env bash
#
# Sample helper: list ArgoCD applications from the terminal.
# Uses the same ~/.config/argocd/config token as the menubar app.
#
# Not required to run the app. Useful for debugging auth and API access.
#
# Prerequisites: curl, jq, yq
# Optional: argocd CLI (only if --login is used)
#
# Usage:
#   ./scripts/list-argocd-apps.sh --server argocd.example.com --project default
#   ARGOCD_SERVER=argocd.example.com ARGOCD_PROJECT=platform ./scripts/list-argocd-apps.sh
#   ./scripts/list-argocd-apps.sh --server argocd.example.com          # all visible apps
#   ./scripts/list-argocd-apps.sh --server argocd.example.com --json
#
# Environment:
#   ARGOCD_SERVER   ArgoCD host (required unless --server is passed)
#   ARGOCD_PROJECT  ArgoCD project filter (optional; omit to list all visible apps)
#   ARGOCD_CONFIG   Path to argocd CLI config (default: ~/.config/argocd/config)
#   ARGOCD_LOGIN_ARGS  Extra args for `argocd login` when using --login
#                      (default: --grpc-web)

set -euo pipefail

SERVER="${ARGOCD_SERVER:-}"
PROJECT="${ARGOCD_PROJECT:-}"
CONFIG="${ARGOCD_CONFIG:-$HOME/.config/argocd/config}"
LOGIN_ARGS="${ARGOCD_LOGIN_ARGS:---grpc-web}"
SKEW=120
JSON=0
DO_LOGIN=0

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --server)
    [[ $# -ge 2 ]] || die "--server requires a value"
    SERVER="$2"
    shift 2
    ;;
  --project)
    [[ $# -ge 2 ]] || die "--project requires a value"
    PROJECT="$2"
    shift 2
    ;;
  --config)
    [[ $# -ge 2 ]] || die "--config requires a value"
    CONFIG="$2"
    shift 2
    ;;
  --json)
    JSON=1
    shift
    ;;
  --login)
    DO_LOGIN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    die "unknown option: $1 (try --help)"
    ;;
  *)
    [[ -z "$SERVER" ]] || die "unexpected argument: $1 (server already set; try --help)"
    SERVER="$1"
    shift
    if [[ $# -gt 0 && "$1" != -* ]]; then
      [[ -z "$PROJECT" ]] || die "unexpected argument: $1 (project already set; try --help)"
      PROJECT="$1"
      shift
    fi
    ;;
  esac
done

[[ -n "$SERVER" ]] || die "missing server: set ARGOCD_SERVER or pass --server"

BASE_URL="https://${SERVER}"

require_cmd() {
  command -v "$1" >/dev/null || die "$1 not found on PATH"
}

get_token() {
  yq -r ".users[] | select(.name == \"$SERVER\") | .\"auth-token\" // \"\"" "$CONFIG" 2>/dev/null
}

token_valid() {
  local token payload exp
  token="$(get_token)"
  [[ -n "$token" ]] || return 1
  payload="$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')"
  case $((${#payload} % 4)) in
  2) payload="${payload}==" ;;
  3) payload="${payload}=" ;;
  esac
  exp="$(printf '%s' "$payload" | base64 -d 2>/dev/null | jq -r '.exp // empty')"
  [[ -n "$exp" ]] || return 1
  [[ "$exp" -gt "$(($(date +%s) + SKEW))" ]]
}

ensure_token() {
  require_cmd jq
  require_cmd yq

  if token_valid; then
    return 0
  fi

  if [[ "$DO_LOGIN" -eq 1 ]]; then
    require_cmd argocd
    echo "Logging in to ${BASE_URL}..." >&2
    # shellcheck disable=SC2086
    argocd login "$SERVER" $LOGIN_ARGS >&2
    token_valid || die "login completed but token for ${SERVER} is still missing or expired"
    return 0
  fi

  cat >&2 <<EOF
No valid token for ${SERVER} in ${CONFIG}.

Log in with the ArgoCD CLI, then re-run this script:

  argocd login ${SERVER} --grpc-web

Or pass --login to run argocd login from this script (set ARGOCD_LOGIN_ARGS if you use SSO):

  ARGOCD_LOGIN_ARGS="--sso --grpc-web" $0 --server ${SERVER} --login
EOF
  exit 1
}

list_apps() {
  local token url
  token="$(get_token)"
  [[ -n "$token" ]] || die "no auth token for ${SERVER}"

  url="${BASE_URL}/api/v1/applications"
  if [[ -n "$PROJECT" ]]; then
    url="${url}?projects=${PROJECT}"
  fi

  curl -sf "$url" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json"
}

print_table() {
  jq -r --arg project "$PROJECT" --arg server "$SERVER" '
    def dest:
      (.spec.destination.name // .spec.destination.server // "unknown") as $cluster
      | (.spec.destination.namespace // "-") as $ns
      | "\($cluster)/\($ns)";
    (.items // []) as $apps
    | if ($apps | length) == 0 then
        if ($project | length) > 0 then
          "No applications found in project \"\($project)\" on \($server)."
        else
          "No applications found on \($server)."
        end
      else
        (["NAME", "SYNC", "HEALTH", "DESTINATION"] | @tsv),
        ($apps[]
          | [
              .metadata.name,
              (.status.sync.status // "Unknown"),
              (.status.health.status // "Unknown"),
              dest
            ]
          | @tsv)
      end
  '
}

main() {
  ensure_token

  if [[ "$JSON" -eq 1 ]]; then
    list_apps | jq .
    return
  fi

  if [[ -n "$PROJECT" ]]; then
    echo "ArgoCD: ${BASE_URL}  project: ${PROJECT}" >&2
  else
    echo "ArgoCD: ${BASE_URL}  (all visible applications)" >&2
  fi
  echo >&2

  list_apps | print_table | column -t -s $'\t'
}

main "$@"

