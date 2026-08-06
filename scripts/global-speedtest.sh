#!/usr/bin/env bash

set -euo pipefail

PROGRAM="$(basename "$0")"
VERSION="2.0.0"
DEFAULT_TIMEOUT=180
DEFAULT_LIMIT=100
MAX_LIMIT=100
API_BASE="https://www.speedtest.net/api/js/servers"

usage() {
  cat <<EOF
Global Speedtest CLI ${VERSION}

Usage:
  ${PROGRAM} install

  ${PROGRAM} list-nodes nearby [limit]
  ${PROGRAM} list-nodes country <country> [limit]
  ${PROGRAM} list-nodes city <city> [country] [limit]
  ${PROGRAM} list-nodes region <keyword> [limit]
  ${PROGRAM} list-nodes search <keyword> [limit]
  ${PROGRAM} list-nodes all <keyword> [limit]

  ${PROGRAM} speedtest node <server-id>
  ${PROGRAM} speedtest nearby [limit]
  ${PROGRAM} speedtest country <country> [limit]
  ${PROGRAM} speedtest city <city> [country] [limit]
  ${PROGRAM} speedtest region <keyword> [limit]
  ${PROGRAM} speedtest search <keyword> [limit]
  ${PROGRAM} speedtest all <keyword> [limit]

  ${PROGRAM} help

Commands:
  install
      Install the official Ookla Speedtest CLI and required packages.
      Supports Debian, Ubuntu, CentOS, RHEL, Rocky Linux and AlmaLinux.

  list-nodes nearby [limit]
      List nodes near the current machine's public IP.

  list-nodes country <country> [limit]
      List nodes whose country exactly matches the supplied country.
      Example:
        ${PROGRAM} list-nodes country Nigeria
        ${PROGRAM} list-nodes country "United States" 100

  list-nodes city <city> [country] [limit]
      List nodes whose city exactly matches the supplied city.
      Supplying the country avoids ambiguity between cities with the same name.
      Examples:
        ${PROGRAM} list-nodes city Lagos
        ${PROGRAM} list-nodes city London "United Kingdom" 100

  list-nodes region <keyword> [limit]
  list-nodes search <keyword> [limit]
  list-nodes all <keyword> [limit]
      Search globally by a free-text keyword. The keyword may match a city,
      country, provider or hostname. "all" means all nodes returned for that
      keyword, not every Ookla server worldwide.
      Examples:
        ${PROGRAM} list-nodes region California 100
        ${PROGRAM} list-nodes search "China Telecom" 100
        ${PROGRAM} list-nodes all Nigeria 100

  speedtest node <server-id>
      Test exactly one Ookla server ID.

  speedtest nearby|country|city|region|search|all ...
      Discover all matching nodes and test them sequentially.
      Sequential execution prevents tests from competing for egress bandwidth.

Limits:
  Node discovery returns at most ${MAX_LIMIT} nodes per query.
  Testing every server worldwide is intentionally not provided because it would
  generate extreme traffic and the public search endpoint is query-based.

Environment variables:
  GLOBAL_SPEEDTEST_TIMEOUT=<seconds>
      Timeout for each node. Default: ${DEFAULT_TIMEOUT}

  GLOBAL_SPEEDTEST_OUTPUT_DIR=<directory>
      Parent directory for generated reports. Default: current directory

  GLOBAL_SPEEDTEST_API_TIMEOUT=<seconds>
      Timeout for server discovery requests. Default: 60

  NO_COLOR=1
      Disable colored progress messages.

Report files:
  report.tsv          Complete tab-separated report
  report.csv          Complete CSV report
  summary.txt         Summary and best results
  selected-nodes.tsv  Nodes selected for the run
  json/*.json         Raw Ookla JSON results
  json/*.err          Error output for failed tests

Notes:
  All operations use subcommands; there are no interactive prompts.
  Quote names containing spaces.
  Region is a free-text search because the server API does not expose a
  consistent administrative-region field for every country.
EOF
}

error_usage() {
  printf 'Error: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

color_enabled() {
  [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

info() {
  if color_enabled; then
    printf '\033[1;36m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

ok() {
  if color_enabled; then
    printf '\033[1;32m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

warn() {
  if color_enabled; then
    printf '\033[1;33m%s\033[0m\n' "$*" >&2
  else
    printf '%s\n' "$*" >&2
  fi
}

fatal() {
  if color_enabled; then
    printf '\033[1;31mError: %s\033[0m\n' "$*" >&2
  else
    printf 'Error: %s\n' "$*" >&2
  fi
  exit 1
}

normalize() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -d ' _-'
}

validate_limit() {
  local limit="$1"
  [[ "$limit" =~ ^[1-9][0-9]*$ ]] \
    || error_usage "limit must be an integer between 1 and ${MAX_LIMIT}."
  (( limit >= 1 && limit <= MAX_LIMIT )) \
    || error_usage "limit must be between 1 and ${MAX_LIMIT}."
}

render_table() {
  local input_file="$1"

  awk -F '\t' '
    {
      rows = NR
      if (NF > cols) cols = NF
      for (i = 1; i <= NF; i++) {
        value[NR, i] = $i
        if (length($i) > width[i]) width[i] = length($i)
        if (NR == 1 && $i ~ /^(ID|DIST|LAT|JIT|LOSS|DOWN|UP)/) right[i] = 1
      }
    }
    function separator(    i, j, line) {
      line = "+"
      for (i = 1; i <= cols; i++) {
        for (j = 1; j <= width[i] + 2; j++) line = line "-"
        line = line "+"
      }
      print line
    }
    END {
      if (rows == 0) exit
      separator()
      for (r = 1; r <= rows; r++) {
        printf "|"
        for (c = 1; c <= cols; c++) {
          if (right[c])
            printf " %*s |", width[c], value[r, c]
          else
            printf " %-*s |", width[c], value[r, c]
        }
        printf "\n"
        if (r == 1) separator()
      }
      separator()
    }
  ' "$input_file"
}

require_root() {
  (( EUID == 0 )) || fatal "install must run as root: sudo ./${PROGRAM} install"
}

install_debian() {
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y ca-certificates curl jq coreutils util-linux gawk
  apt-get install -y bsdextrautils >/dev/null 2>&1 || true

  if dpkg-query -W -f='${Status}' speedtest-cli 2>/dev/null | grep -q 'install ok installed'; then
    apt-get remove -y speedtest-cli
  fi

  curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
  apt-get install -y speedtest
}

install_rhel() {
  local pkgmgr

  if command -v dnf >/dev/null 2>&1; then
    pkgmgr="dnf"
  elif command -v yum >/dev/null 2>&1; then
    pkgmgr="yum"
  else
    fatal "Neither dnf nor yum was found."
  fi

  "$pkgmgr" install -y ca-certificates curl jq coreutils util-linux gawk

  if rpm -q speedtest-cli >/dev/null 2>&1; then
    "$pkgmgr" remove -y speedtest-cli
  fi

  curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash
  "$pkgmgr" install -y speedtest
}

command_install() {
  local distro_id distro_like

  [[ "$#" -eq 0 ]] || error_usage "install takes no arguments."
  require_root

  [[ -r /etc/os-release ]] \
    || fatal "/etc/os-release was not found; distribution detection failed."

  # shellcheck disable=SC1091
  . /etc/os-release
  distro_id="${ID:-}"
  distro_like="${ID_LIKE:-}"

  case " ${distro_id} ${distro_like} " in
    *debian*|*ubuntu*)
      info "Detected Debian-family distribution."
      install_debian
      ;;
    *rhel*|*fedora*|*centos*|*rocky*|*almalinux*)
      info "Detected RHEL-family distribution."
      install_rhel
      ;;
    *)
      fatal "Unsupported distribution: ID=${distro_id}, ID_LIKE=${distro_like}"
      ;;
  esac

  check_runtime_dependencies
  ok "Installation completed successfully."
  speedtest --version
}

check_discovery_dependencies() {
  local cmd
  for cmd in curl jq awk sed tr sort; do
    command -v "$cmd" >/dev/null 2>&1 \
      || fatal "Missing command '${cmd}'. Run: sudo ./${PROGRAM} install"
  done
}

check_runtime_dependencies() {
  local cmd
  check_discovery_dependencies

  for cmd in speedtest timeout; do
    command -v "$cmd" >/dev/null 2>&1 \
      || fatal "Missing command '${cmd}'. Run: sudo ./${PROGRAM} install"
  done

  speedtest --version 2>&1 | grep -qi 'ookla' \
    || fatal "The installed speedtest command is not the official Ookla CLI."
}

urlencode() {
  jq -rn --arg value "$1" '$value | @uri'
}

fetch_nodes_json() {
  local query="$1"
  local limit="$2"
  local api_timeout="${GLOBAL_SPEEDTEST_API_TIMEOUT:-60}"
  local url encoded response_file

  [[ "$api_timeout" =~ ^[1-9][0-9]*$ ]] \
    || fatal "GLOBAL_SPEEDTEST_API_TIMEOUT must be a positive integer."

  encoded="$(urlencode "$query")"
  url="${API_BASE}?engine=js&https_functional=true&limit=${limit}"
  [[ -z "$query" ]] || url="${url}&search=${encoded}"

  response_file="$(mktemp)"
  if ! curl -fsSL \
      --retry 2 \
      --retry-delay 1 \
      --connect-timeout 10 \
      --max-time "$api_timeout" \
      --user-agent "Mozilla/5.0 global-speedtest/${VERSION}" \
      "$url" > "$response_file"; then
    rm -f "$response_file"
    fatal "Failed to query the Speedtest server directory."
  fi

  if ! jq -e 'type == "array"' "$response_file" >/dev/null 2>&1; then
    rm -f "$response_file"
    fatal "The Speedtest server directory returned an unexpected response."
  fi

  cat "$response_file"
  rm -f "$response_file"
}

# Output format:
# ID<TAB>CITY<TAB>COUNTRY<TAB>CC<TAB>PROVIDER<TAB>HOST<TAB>DISTANCE_KM
json_to_nodes() {
  jq -r '
    def clean:
      tostring
      | gsub("[\\t\\r\\n]+"; " ")
      | gsub("  +"; " ");

    unique_by(.id)
    | sort_by((.distance | tonumber? // 999999), (.country // ""), (.name // ""), (.id | tonumber? // 0))
    | .[]
    | [
        (.id // "-" | clean),
        (.name // "-" | clean),
        (.country // "-" | clean),
        (.cc // "-" | clean),
        (.sponsor // "-" | clean),
        (.host // "-" | clean),
        ((.distance // "-") | clean)
      ]
    | @tsv
  '
}

parse_scope() {
  # Prints fields separated by ASCII unit separator (0x1f).
  local mode="${1:-}"
  shift || true
  local query="" country="" limit="$DEFAULT_LIMIT"

  case "$mode" in
    nearby)
      case "$#" in
        0) ;;
        1) limit="$1" ;;
        *) error_usage "nearby accepts only an optional limit." ;;
      esac
      ;;

    country)
      case "$#" in
        1) query="$1" ;;
        2) query="$1"; limit="$2" ;;
        *) error_usage "country requires <country> and an optional limit." ;;
      esac
      ;;

    city)
      case "$#" in
        1)
          query="$1"
          ;;
        2)
          query="$1"
          if [[ "$2" =~ ^[0-9]+$ ]]; then
            limit="$2"
          else
            country="$2"
          fi
          ;;
        3)
          query="$1"
          country="$2"
          limit="$3"
          ;;
        *)
          error_usage "city requires <city>, optional [country], and optional [limit]."
          ;;
      esac
      ;;

    region|search|all)
      case "$#" in
        1) query="$1" ;;
        2) query="$1"; limit="$2" ;;
        *) error_usage "${mode} requires <keyword> and an optional limit." ;;
      esac
      ;;

    *)
      error_usage "Unknown selector: ${mode}"
      ;;
  esac

  validate_limit "$limit"
  printf '%s\x1f%s\x1f%s\x1f%s\n' "$mode" "$query" "$country" "$limit"
}

discover_nodes() {
  local mode="$1"
  local query="$2"
  local country="$3"
  local limit="$4"
  local query_for_api json_file query_norm country_norm

  case "$mode" in
    nearby)
      query_for_api=""
      ;;
    country|city|region|search|all)
      query_for_api="$query"
      ;;
    *)
      fatal "Internal error: unsupported discovery mode '${mode}'."
      ;;
  esac

  json_file="$(mktemp)"
  fetch_nodes_json "$query_for_api" "$limit" > "$json_file"

  query_norm="$(normalize "$query")"
  country_norm="$(normalize "$country")"

  case "$mode" in
    nearby|region|search|all)
      json_to_nodes < "$json_file"
      ;;

    country)
      jq --arg wanted "$query_norm" '
        map(select(
          ((.country // "") | ascii_downcase | gsub("[ _-]"; "")) == $wanted
          or ((.cc // "") | ascii_downcase) == $wanted
        ))
      ' "$json_file" | json_to_nodes
      ;;

    city)
      jq --arg city "$query_norm" --arg country "$country_norm" '
        map(select(
          ((.name // "") | ascii_downcase | gsub("[ _-]"; "")) == $city
          and (
            $country == ""
            or ((.country // "") | ascii_downcase | gsub("[ _-]"; "")) == $country
            or ((.cc // "") | ascii_downcase) == $country
          )
        ))
      ' "$json_file" | json_to_nodes
      ;;
  esac

  rm -f "$json_file"
}

truncate_text() {
  local text="$1"
  local max="$2"
  if (( ${#text} <= max )); then
    printf '%s' "$text"
  else
    printf '%s...' "${text:0:max-3}"
  fi
}

list_nodes_from_file() {
  local selected_file="$1"
  local table_file
  table_file="$(mktemp)"

  printf 'ID\tCITY\tCOUNTRY\tCC\tPROVIDER\tHOST\tDIST(km)\n' > "$table_file"

  while IFS=$'\t' read -r id city country cc provider host distance; do
    [[ -n "$id" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" \
      "$(truncate_text "$city" 22)" \
      "$(truncate_text "$country" 22)" \
      "$cc" \
      "$(truncate_text "$provider" 32)" \
      "$(truncate_text "$host" 46)" \
      "$distance" >> "$table_file"
  done < "$selected_file"

  render_table "$table_file"
  rm -f "$table_file"
}

write_selected_nodes() {
  local mode="$1"
  local query="$2"
  local country="$3"
  local limit="$4"
  local output_file="$5"
  local count

  discover_nodes "$mode" "$query" "$country" "$limit" > "$output_file"
  count="$(awk 'NF { count++ } END { print count + 0 }' "$output_file")"

  if (( count == 0 )); then
    if [[ "$mode" == "city" && -n "$country" ]]; then
      fatal "No nodes found for city '${query}' in country '${country}'."
    fi
    fatal "No nodes found for ${mode} '${query}'."
  fi
}

command_list_nodes() {
  local parsed mode query country limit selected_file

  [[ "$#" -ge 1 ]] || error_usage "list-nodes requires a selector."
  check_discovery_dependencies

  parsed="$(parse_scope "$@")"
  IFS=$'\x1f' read -r mode query country limit <<< "$parsed"

  selected_file="$(mktemp)"
  write_selected_nodes "$mode" "$query" "$country" "$limit" "$selected_file"

  printf 'Selector: %s' "$mode"
  [[ -z "$query" ]] || printf ' / %s' "$query"
  [[ -z "$country" ]] || printf ' / %s' "$country"
  printf '\nNodes   : %s\n\n' "$(awk 'NF { n++ } END { print n + 0 }' "$selected_file")"

  list_nodes_from_file "$selected_file"
  rm -f "$selected_file"
}

sanitize_error() {
  local error_file="$1"
  local message

  message="$(tr '\n\t' '  ' < "$error_file" \
    | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' \
    | cut -c1-180)"

  [[ -n "$message" ]] || message="Speed test failed"
  printf '%s' "$message"
}

write_csv() {
  local tsv_file="$1"
  local csv_file="$2"

  jq -R -s -r '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | .[]
    | @csv
  ' "$tsv_file" > "$csv_file"
}

sort_report() {
  local report_file="$1"
  local sorted_file="$2"

  {
    head -n 1 "$report_file"
    awk -F '\t' 'NR > 1 && $12 == "OK"' "$report_file" \
      | sort -t $'\t' -k10,10gr
    awk -F '\t' 'NR > 1 && $12 != "OK"' "$report_file"
  } > "$sorted_file"
}

build_summary() {
  local report_file="$1"
  local summary_file="$2"
  local selector="$3"
  local total ok_count fail_count best_download best_upload best_latency

  total="$(awk -F '\t' 'NR > 1 { n++ } END { print n + 0 }' "$report_file")"
  ok_count="$(awk -F '\t' 'NR > 1 && $12 == "OK" { n++ } END { print n + 0 }' "$report_file")"
  fail_count=$((total - ok_count))

  best_download="$(awk -F '\t' 'NR > 1 && $12 == "OK" { print $10 " Mbps - " $1 " / " $2 " / " $3 " / " $5 }' "$report_file" | sort -gr | head -n 1)"
  best_upload="$(awk -F '\t' 'NR > 1 && $12 == "OK" { print $11 " Mbps - " $1 " / " $2 " / " $3 " / " $5 }' "$report_file" | sort -gr | head -n 1)"
  best_latency="$(awk -F '\t' 'NR > 1 && $12 == "OK" { print $7 " ms - " $1 " / " $2 " / " $3 " / " $5 }' "$report_file" | sort -g | head -n 1)"

  {
    printf 'Global Speedtest Report\n'
    printf 'Generated       : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'Selector        : %s\n' "$selector"
    printf 'Total nodes     : %s\n' "$total"
    printf 'Successful      : %s\n' "$ok_count"
    printf 'Failed          : %s\n' "$fail_count"
    printf 'Best download   : %s\n' "${best_download:--}"
    printf 'Best upload     : %s\n' "${best_upload:--}"
    printf 'Lowest latency  : %s\n' "${best_latency:--}"
  } > "$summary_file"
}

run_one_speedtest() {
  local id="$1"
  local fallback_city="$2"
  local fallback_country="$3"
  local fallback_cc="$4"
  local fallback_provider="$5"
  local fallback_distance="$6"
  local timeout_seconds="$7"
  local json_file="$8"
  local err_file="$9"
  local report_file="${10}"
  local status_code error_message

  set +e
  timeout "${timeout_seconds}s" speedtest \
    --accept-license \
    --accept-gdpr \
    --server-id="$id" \
    --format=json \
    > "$json_file" 2> "$err_file"
  status_code=$?
  set -e

  if [[ "$status_code" -eq 0 ]] && jq -e . "$json_file" >/dev/null 2>&1; then
    jq -r \
      --arg id "$id" \
      --arg fallback_city "$fallback_city" \
      --arg fallback_country "$fallback_country" \
      --arg fallback_cc "$fallback_cc" \
      --arg fallback_provider "$fallback_provider" \
      --arg fallback_distance "$fallback_distance" '
        def rounded:
          (tonumber?) as $n
          | if $n == null then "-"
            else ((($n * 100) | round) / 100 | tostring)
            end;
        def clean:
          tostring | gsub("[\\t\\r\\n]+"; " ") | gsub("  +"; " ");

        [
          (.server.id // $id | tostring),
          (.server.country // $fallback_country // "-" | clean),
          (.server.location // .server.name // $fallback_city // "-" | clean),
          (.server.countryCode // .server.cc // $fallback_cc // "-" | clean),
          (.server.sponsor // $fallback_provider // "-" | clean),
          (.server.distance // $fallback_distance | rounded),
          (.ping.latency | rounded),
          (.ping.jitter | rounded),
          (.packetLoss | rounded),
          (((.download.bandwidth | tonumber? // 0) * 8 / 1000000) | rounded),
          (((.upload.bandwidth | tonumber? // 0) * 8 / 1000000) | rounded),
          "OK",
          (.result.url // "-")
        ] | @tsv
      ' "$json_file" >> "$report_file"

    jq -r '
      def rounded_str:
        (tonumber?) as $n
        | if $n == null then "0"
          else ((($n * 100) | round) / 100 | tostring)
          end;

      "  OK  latency=" + ((.ping.latency | rounded_str)) + " ms" +
      "  download=" + (((.download.bandwidth | tonumber? // 0) * 8 / 1000000) | rounded_str) + " Mbps" +
      "  upload=" + (((.upload.bandwidth | tonumber? // 0) * 8 / 1000000) | rounded_str) + " Mbps"
    ' "$json_file"
    return 0
  fi

  if [[ "$status_code" -eq 124 ]]; then
    error_message="Timed out after ${timeout_seconds}s"
  else
    error_message="$(sanitize_error "$err_file")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\t-\tFAIL\t%s\n' \
    "$id" "$fallback_country" "$fallback_city" "$fallback_cc" \
    "$fallback_provider" "$fallback_distance" "$error_message" \
    >> "$report_file"
  warn "  FAIL  ${error_message}"
  return 1
}

command_speedtest() {
  local mode query country limit parsed selector timeout_seconds
  local output_parent report_dir json_dir selected_file report_file sorted_file display_file
  local id city node_country cc provider host distance json_file err_file
  local total index

  [[ "$#" -ge 1 ]] || error_usage "speedtest requires a selector."

  if [[ "$1" == "node" ]]; then
    [[ "$#" -eq 2 ]] || error_usage "speedtest node requires exactly one numeric server ID."
    [[ "$2" =~ ^[0-9]+$ ]] || error_usage "server ID must be numeric."
    mode="node"
    query="$2"
    country=""
    limit="1"
    selector="node: ${query}"
  else
    parsed="$(parse_scope "$@")"
    IFS=$'\x1f' read -r mode query country limit <<< "$parsed"
    selector="$mode"
    [[ -z "$query" ]] || selector="${selector}: ${query}"
    [[ -z "$country" ]] || selector="${selector}, country: ${country}"
  fi

  timeout_seconds="${GLOBAL_SPEEDTEST_TIMEOUT:-$DEFAULT_TIMEOUT}"
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] \
    || fatal "GLOBAL_SPEEDTEST_TIMEOUT must be a positive integer."

  check_runtime_dependencies

  output_parent="${GLOBAL_SPEEDTEST_OUTPUT_DIR:-$PWD}"
  mkdir -p "$output_parent" \
    || fatal "Cannot create output directory: ${output_parent}"

  report_dir="${output_parent%/}/global-speedtest-$(date +%Y%m%d-%H%M%S)-$$"
  json_dir="$report_dir/json"
  selected_file="$report_dir/selected-nodes.tsv"
  report_file="$report_dir/report.tsv"
  sorted_file="$report_dir/report.sorted.tsv"
  display_file="$report_dir/report.display.tsv"

  mkdir -p "$json_dir" \
    || fatal "Cannot create report directory: ${report_dir}"

  if [[ "$mode" == "node" ]]; then
    printf '%s\t-\t-\t-\t-\t-\t-\n' "$query" > "$selected_file"
  else
    write_selected_nodes "$mode" "$query" "$country" "$limit" "$selected_file"
  fi

  total="$(awk 'NF { n++ } END { print n + 0 }' "$selected_file")"
  index=0

  printf 'ID\tCOUNTRY\tCITY\tCC\tPROVIDER\tDISTANCE_KM\tLATENCY_MS\tJITTER_MS\tLOSS_PCT\tDOWNLOAD_MBPS\tUPLOAD_MBPS\tSTATUS\tRESULT\n' \
    > "$report_file"

  info "Selector : ${selector}"
  info "Nodes    : ${total}"
  info "Timeout  : ${timeout_seconds}s per node"
  info "Output   : ${report_dir}"
  printf '\n'

  while IFS=$'\t' read -r id city node_country cc provider host distance; do
    [[ -n "$id" ]] || continue
    index=$((index + 1))
    json_file="$json_dir/${id}.json"
    err_file="$json_dir/${id}.err"

    info "[${index}/${total}] Testing ${id} / ${node_country} / ${city} / ${provider} ..."

    run_one_speedtest \
      "$id" "$city" "$node_country" "$cc" "$provider" "$distance" \
      "$timeout_seconds" "$json_file" "$err_file" "$report_file" || true
  done < "$selected_file"

  sort_report "$report_file" "$sorted_file"
  mv "$sorted_file" "$report_file"
  write_csv "$report_file" "$report_dir/report.csv"
  build_summary "$report_file" "$report_dir/summary.txt" "$selector"

  # Compact terminal report. Full values remain in TSV and CSV.
  printf 'ID\tCOUNTRY\tCITY\tPROVIDER\tLAT(ms)\tJIT(ms)\tLOSS%%\tDOWN(Mbps)\tUP(Mbps)\tSTATUS\tRESULT\n' \
    > "$display_file"

  while IFS=$'\t' read -r id node_country city cc provider distance latency jitter loss download upload status result; do
    [[ "$id" == "ID" ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" \
      "$(truncate_text "$node_country" 18)" \
      "$(truncate_text "$city" 20)" \
      "$(truncate_text "$provider" 28)" \
      "$latency" "$jitter" "$loss" "$download" "$upload" "$status" \
      "$(truncate_text "$result" 48)" >> "$display_file"
  done < "$report_file"

  printf '\n'
  info "============================== SPEEDTEST REPORT =============================="
  render_table "$display_file"
  printf '\n'
  cat "$report_dir/summary.txt"
  printf '\n'
  ok "Report directory: ${report_dir}"
  printf 'TSV report      : %s\n' "$report_file"
  printf 'CSV report      : %s\n' "$report_dir/report.csv"
  printf 'Summary         : %s\n' "$report_dir/summary.txt"
  printf 'Selected nodes  : %s\n' "$selected_file"
  printf 'Raw JSON/errors : %s\n' "$json_dir"
}

main() {
  local command="${1:-}"

  case "$command" in
    help)
      [[ "$#" -eq 1 ]] || error_usage "help takes no arguments."
      usage
      ;;

    install)
      shift
      command_install "$@"
      ;;

    list-nodes)
      shift
      command_list_nodes "$@"
      ;;

    speedtest)
      shift
      command_speedtest "$@"
      ;;

    "")
      error_usage "A subcommand is required."
      ;;

    *)
      error_usage "Unknown subcommand: ${command}"
      ;;
  esac
}

main "$@"