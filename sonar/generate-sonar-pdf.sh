#!/bin/bash
set -e

#################################################
# CONFIGURATION
#################################################
SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"

# Jenkins / Git info
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse --short HEAD)

# Files
WORKDIR="sonar-report-work"
JSON_ALL="${WORKDIR}/issues.json"
HTML_OUT="sonar-report.html"
PDF_OUT="sonar-report.pdf"
TEMPLATE_FILE="sonar/sonar-executive-report.html"

# Pagination
PAGE_SIZE=200
MAX_PAGES=10   # max 2000 issues (safe limit)

#################################################
# PRE-CHECKS
#################################################
echo "Preparing SonarQube report directory..."
rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}

echo "Checking required tools..."
jq --version
wkhtmltopdf --version

if [ -z "$SONAR_TOKEN" ]; then
  echo "❌ SONAR_TOKEN not set"
  exit 1
fi

if [ ! -f "${TEMPLATE_FILE}" ]; then
  echo "❌ HTML template not found: ${TEMPLATE_FILE}"
  exit 1
fi

#################################################
# FETCH ISSUES (PAGINATED + TIMEOUT SAFE)
#################################################
echo "Fetching issues from SonarQube..."

echo '{"issues":[],"total":0}' > ${JSON_ALL}

for ((PAGE=1; PAGE<=MAX_PAGES; PAGE++)); do
  echo "→ Fetching page ${PAGE}..."

  RESP=$(curl --connect-timeout 10 \
              --max-time 60 \
              -s -u ${SONAR_TOKEN}: \
              "${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&p=${PAGE}&ps=${PAGE_SIZE}")

  COUNT=$(echo "$RESP" | jq '.issues | length')

  if [ "$COUNT" -eq 0 ]; then
    echo "No more issues found, stopping pagination."
    break
  fi

  jq -s '
    .[0].issues += .[1].issues |
    .[0].total += .[1].total
  ' ${JSON_ALL} <(echo "$RESP") > ${JSON_ALL}.tmp

  mv ${JSON_ALL}.tmp ${JSON_ALL}
done

#################################################
# METRICS CALCULATION
#################################################
TOTAL_ISSUES=$(jq '.issues | length' ${JSON_ALL})
BUGS=$(jq '[.issues[] | select(.type=="BUG")] | length' ${JSON_ALL})
VULNERABILITIES=$(jq '[.issues[] | select(.type=="VULNERABILITY")] | length' ${JSON_ALL})
CODE_SMELLS=$(jq '[.issues[] | select(.type=="CODE_SMELL")] | length' ${JSON_ALL})
SECURITY_HOTSPOTS=$(jq '[.issues[] | select(.securityHotspot==true)] | length' ${JSON_ALL})

#################################################
# QUALITY GATE STATUS (PROD LOGIC)
#################################################
if [ "$VULNERABILITIES" -gt 0 ]; then
  QUALITY_GATE="FAILED"
  QG_CLASS="_
