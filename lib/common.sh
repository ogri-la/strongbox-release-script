# shared by the host-side pipelines `prep.sh` and `release.sh`. sourced, not executed.
# the host needs only `bash`, coreutils and `docker`, so nothing here calls any other tool.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-$ROOT/.github-token}"
AUR_KEY_FILE="${AUR_KEY_FILE:-$HOME/.ssh/aur}"

# --- logging
# structured `key=value` lines on stderr. `LOG_LEVEL` is one of DEBUG, INFO (default), WARN, ERROR.

declare -A LOG_LEVELS=([DEBUG]=10 [INFO]=20 [WARN]=30 [ERROR]=40)
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

log() {
    local level="$1" msg="$2"
    shift 2
    if [ "${LOG_LEVELS[$level]}" -lt "${LOG_LEVELS[$LOG_LEVEL]:-20}" ]; then
        return 0
    fi
    local line
    printf -v line 'level=%s msg="%s"' "$level" "$msg"
    local pair
    for pair in "$@"; do
        line+=" $pair"
    done
    printf '%s\n' "$line" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

# --- inputs

valid_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# reads `pins.env` into the associative array `PINS`, ignoring comments and blank lines
declare -A PINS
load_pins() {
    local line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^([A-Z0-9_]+)=(.*)$ ]] || die "malformed line in pins.env" "line=\"$line\""
        PINS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    done < "$ROOT/pins.env"
}

# reads `config.env` into the environment of this process
load_config() {
    local line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^([A-Z0-9_]+)=(.*)$ ]] || die "malformed line in config.env" "line=\"$line\""
        export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    done < "$ROOT/config.env"
}

require_docker() {
    command -v docker > /dev/null || die "docker is not installed, it is the only host prerequisite besides bash"
    docker info > /dev/null 2>&1 || die "the docker daemon is not reachable" "hint=\"sudo systemctl start docker\""
}

# --- interaction

# shows nothing itself. asks for `expected` to be typed and fails unless it is.
# without a terminal, refuses unless `ASSUME_YES=1`.
confirm() {
    local prompt="$1" expected="$2"
    if [ "${ASSUME_YES:-0}" = 1 ]; then
        log WARN "confirmation skipped because ASSUME_YES=1" "expected=$expected"
        return 0
    fi
    if [ ! -t 0 ]; then
        die "confirmation needs a terminal; refusing to continue" "hint=\"rerun interactively, or set ASSUME_YES=1\""
    fi
    local answer
    read -r -p "$prompt " answer
    [ "$answer" = "$expected" ] || die "not confirmed, nothing remote was changed" "expected=\"$expected\""
}
