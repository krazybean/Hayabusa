#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${WINDOWS_TEMPLATE_FILE:-${ROOT_DIR}/configs/fluent-bit/windows/fluent-bit-windows.conf}"
OUTPUT_BASE_DIR="${WINDOWS_OUTPUT_DIR:-${ROOT_DIR}/dist/windows-endpoints}"
ENDPOINT_ID=""
VECTOR_HOST=""
FORCE=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/enroll-windows-endpoint.sh --endpoint-id <id> --vector-host <host-or-ip> [options]

Options:
  --endpoint-id <id>      Endpoint identifier for bundle output path
  --vector-host <value>   Reachable Hayabusa host/IP for Vector Windows lane (24225)
  --template-file <path>  Fluent Bit template (default: configs/fluent-bit/windows/fluent-bit-windows.conf)
  --output-dir <path>     Output base dir (default: dist/windows-endpoints)
  --force                 Overwrite existing bundle dir
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint-id)
      ENDPOINT_ID="${2:-}"
      shift 2
      ;;
    --vector-host)
      VECTOR_HOST="${2:-}"
      shift 2
      ;;
    --template-file)
      TEMPLATE_FILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_BASE_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${ENDPOINT_ID}" || -z "${VECTOR_HOST}" ]]; then
  usage
  exit 1
fi

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "ERROR: template file not found: ${TEMPLATE_FILE}" >&2
  exit 1
fi

if [[ ! "${ENDPOINT_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: endpoint-id must match [A-Za-z0-9._-]+" >&2
  exit 1
fi

bundle_dir="${OUTPUT_BASE_DIR}/${ENDPOINT_ID}"
if [[ -e "${bundle_dir}" && "${FORCE}" != "true" ]]; then
  echo "ERROR: ${bundle_dir} already exists. Re-run with --force to overwrite." >&2
  exit 1
fi

rm -rf "${bundle_dir}"
mkdir -p "${bundle_dir}"

awk -v host="${VECTOR_HOST}" '
  { gsub(/HAYABUSA_VECTOR_HOST/, host) }
  { print }
' "${TEMPLATE_FILE}" > "${bundle_dir}/fluent-bit.conf"

cat > "${bundle_dir}/README.txt" <<EOF
Hayabusa Windows endpoint bundle
Endpoint ID: ${ENDPOINT_ID}
Generated (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Copy:
  ${bundle_dir}/fluent-bit.conf

Suggested target path on Windows:
  C:\\fluent-bit\\conf\\fluent-bit.conf

Interactive test command on Windows:
  C:\\fluent-bit\\bin\\fluent-bit.exe -c C:\\fluent-bit\\conf\\fluent-bit.conf

Vector target:
  ${VECTOR_HOST}:24225

Validation on Hayabusa host:
  ./scripts/windows-endpoint-check.sh --computer ${ENDPOINT_ID}
  ./scripts/endpoint-activity-report.sh --lane vector-windows-endpoint --min-endpoints 1
EOF

echo "Created Windows endpoint bundle:"
echo "  ${bundle_dir}"
echo "  ${bundle_dir}/fluent-bit.conf"
echo "  ${bundle_dir}/README.txt"
