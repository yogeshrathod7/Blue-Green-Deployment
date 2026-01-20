#!/bin/bash
set -e

SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse --short HEAD)

JSON="sonar-report.json"
HTML="sonar-report.html"
PDF="sonar-report.pdf"
TEMPLATE="sonar/sonar-executive-report.html"

curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&ps=500" \
-o ${JSON}

TOTAL=$(jq '.total' ${JSON})
BUGS=$(jq '[.issues[]|select(.type=="BUG")]|length' ${JSON})
VULNS=$(jq '[.issues[]|select(.type=="VULNERABILITY")]|length' ${JSON})
SMELLS=$(jq '[.issues[]|select(.type=="CODE_SMELL")]|length' ${JSON})
HOTSPOTS=$(jq '[.issues[]|select(.securityHotspot==true)]|length' ${JSON})

QG="FAILED"
QG_CLASS="fail"

ISSUE_ROWS=$(jq -r '
  .issues[] |
  "<tr><td>" + .type + "</td>" +
  "<td class=\"severity-" + .severity + "\">" + .severity + "</td>" +
  "<td>" + .component + "</td>" +
  "<td>" + ((.line|tostring)//"NA") + "</td>" +
  "<td>" + .message + "</td></tr>"
' ${JSON})

sed -e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
    -e "s|{{BRANCH}}|${BRANCH}|g" \
    -e "s|{{COMMIT_ID}}|${COMMIT_ID}|g" \
    -e "s|{{GENERATED_DATE}}|$(date)|g" \
    -e "s|{{QUALITY_GATE}}|${QG}|g" \
    -e "s|{{QG_CLASS}}|${QG_CLASS}|g" \
    -e "s|{{TOTAL_ISSUES}}|${TOTAL}|g" \
    -e "s|{{BUGS}}|${BUGS}|g" \
    -e "s|{{VULNERABILITIES}}|${VULNS}|g" \
    -e "s|{{SECURITY_HOTSPOTS}}|${HOTSPOTS}|g" \
    -e "s|{{CODE_SMELLS}}|${SMELLS}|g" \
    -e "s|{{ISSUE_ROWS}}|${ISSUE_ROWS}|g" \
    ${TEMPLATE} > ${HTML}

wkhtmltopdf ${HTML} ${PDF}
