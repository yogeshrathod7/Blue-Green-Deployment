#!/bin/bash
set -e

#################################################
# CONFIG
#################################################
SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse --short HEAD)

WORKDIR="sonar-report-work"
ISSUES_JSON="${WORKDIR}/issues.json"
HTML_OUT="sonar-report.html"
PDF_OUT="sonar-report.pdf"
TEMPLATE_FILE="sonar/sonar-executive-report.html"

PAGE_SIZE=200
MAX_PAGES=10

#################################################
# PREP
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
  echo "❌ HTML template not found"
  exit 1
fi

#################################################
# FETCH ISSUES (ARRAY-ONLY SAFE METHOD)
#################################################
echo "Fetching issues from SonarQube..."

echo '[]' > ${ISSUES_JSON}

for ((PAGE=1; PAGE<=MAX_PAGES; PAGE++)); do
  echo "→ Fetching page ${PAGE}..."

  RESP=$(curl --connect-timeout 10 \
              --max-time 60 \
              -s -u ${SONAR_TOKEN}: \
              "${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&p=${PAGE}&ps=${PAGE_SIZE}")

  PAGE_COUNT=$(echo "$RESP" | jq '.issues | length')

  if [ "$PAGE_COUNT" -eq 0 ]; then
    echo "No more issues found, stopping pagination."
    break
  fi

  jq -s '.[0] + .[1]' \
     ${ISSUES_JSON} <(echo "$RESP" | jq '.issues') \
     > ${ISSUES_JSON}.tmp

  mv ${ISSUES_JSON}.tmp ${ISSUES_JSON}
done

#################################################
# METRICS
#################################################
TOTAL_ISSUES=$(jq 'length' ${ISSUES_JSON})
BUGS=$(jq '[.[] | select(.type=="BUG")] | length' ${ISSUES_JSON})
VULNERABILITIES=$(jq '[.[] | select(.type=="VULNERABILITY")] | length' ${ISSUES_JSON})
CODE_SMELLS=$(jq '[.[] | select(.type=="CODE_SMELL")] | length' ${ISSUES_JSON})
SECURITY_HOTSPOTS=$(jq '[.[] | select(.securityHotspot==true)] | length' ${ISSUES_JSON})

#################################################
# QUALITY GATE (PROD RULE)
#################################################
if [ "$VULNERABILITIES" -gt 0 ]; then
  QUALITY_GATE="FAILED"
  QG_CLASS="fail"
else
  QUALITY_GATE="PASSED"
  QG_CLASS="pass"
fi

#################################################
# BASE HTML
#################################################
echo "Generating base HTML report..."

sed \
  -e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
  -e "s|{{ENVIRONMENT}}|${ENVIRONMENT}|g" \
  -e "s|{{BRANCH}}|${BRANCH_NAME}|g" \
  -e "s|{{COMMIT_ID}}|${COMMIT_ID}|g" \
  -e "s|{{GENERATED_DATE}}|$(date)|g" \
  -e "s|{{QUALITY_GATE}}|${QUALITY_GATE}|g" \
  -e "s|{{QG_CLASS}}|${QG_CLASS}|g" \
  -e "s|{{TOTAL_ISSUES}}|${TOTAL_ISSUES}|g" \
  -e "s|{{BUGS}}|${BUGS}|g" \
  -e "s|{{VULNERABILITIES}}|${VULNERABILITIES}|g" \
  -e "s|{{SECURITY_HOTSPOTS}}|${SECURITY_HOTSPOTS}|g" \
  -e "s|{{CODE_SMELLS}}|${CODE_SMELLS}|g" \
  -e "s|{{ISSUE_ROWS}}||g" \
  ${TEMPLATE_FILE} > ${HTML_OUT}

#################################################
# INSERT ISSUE ROWS
#################################################
echo "Adding detailed issue rows..."

jq -r '
  .[] |
  "<tr>" +
  "<td>" + .type + "</td>" +
  "<td class=\"severity-" + .severity + "\">" + .severity + "</td>" +
  "<td>" + .component + "</td>" +
  "<td>" + ((.line|tostring)//"NA") + "</td>" +
  "<td>" + .message + "</td>" +
  "</tr>"
' ${ISSUES_JSON} >> ${HTML_OUT}

#################################################
# HTML → PDF
#################################################
echo "Converting HTML to PDF..."
wkhtmltopdf ${HTML_OUT} ${PDF_OUT}

#################################################
# DONE
#################################################
echo "✅ SonarQube Production Executive PDF generated successfully"
echo "Commit ID: ${COMMIT_ID}"
echo "Quality Gate: ${QUALITY_GATE}"
echo "Vulnerabilities: ${VULNERABILITIES}"
ls -lh ${PDF_OUT}
