#!/bin/bash
set -e

############################################
# CONFIGURATION
############################################
SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"
QUALITY_GATE="ERROR"   # PASSED / ERROR (Jenkins Quality Gate se align kar sakte ho)

TEMPLATE_FILE="sonar/sonar-executive-report.html"
HTML_OUTPUT="sonar-report.html"
PDF_OUTPUT="sonar-report.pdf"
JSON_OUTPUT="sonar-report.json"

############################################
# PRE-CHECKS
############################################
echo "🔎 Checking required tools..."
jq --version
wkhtmltopdf --version

if [ -z "$SONAR_TOKEN" ]; then
  echo "❌ SONAR_TOKEN not set"
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ HTML template not found: $TEMPLATE_FILE"
  exit 1
fi

############################################
# FETCH DATA FROM SONARQUBE
############################################
echo "📥 Fetching SonarQube issues..."
curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&ps=500" \
-o ${JSON_OUTPUT}

############################################
# METRICS CALCULATION
############################################
TOTAL_ISSUES=$(jq '.total' ${JSON_OUTPUT})
BUGS=$(jq '[.issues[] | select(.type=="BUG")] | length' ${JSON_OUTPUT})
VULNS=$(jq '[.issues[] | select(.type=="VULNERABILITY")] | length' ${JSON_OUTPUT})
CODE_SMELLS=$(jq '[.issues[] | select(.type=="CODE_SMELL")] | length' ${JSON_OUTPUT})

############################################
# BUILD ISSUE TABLE ROWS (jq-safe)
############################################
echo "🧩 Building issue rows..."

ISSUE_ROWS=$(jq -r '
  .issues[] |
  "<tr>" +
  "<td>" + .type + "</td>" +
  "<td class=\"severity-" + .severity + "\">" + .severity + "</td>" +
  "<td>" + .component + "</td>" +
  "<td>" + ((.line | tostring) // "NA") + "</td>" +
  "<td>" + .message + "</td>" +
  "</tr>"
' ${JSON_OUTPUT})

############################################
# GENERATE FINAL HTML FROM TEMPLATE
############################################
echo "📝 Generating HTML report..."

sed -e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
    -e "s|{{ENVIRONMENT}}|${ENVIRONMENT}|g" \
    -e "s|{{GENERATED_DATE}}|$(date)|g" \
    -e "s|{{QUALITY_GATE}}|${QUALITY_GATE}|g" \
    -e "s|{{TOTAL_ISSUES}}|${TOTAL_ISSUES}|g" \
    -e "s|{{BUGS}}|${BUGS}|g" \
    -e "s|{{VULNERABILITIES}}|${VULNS}|g" \
    -e "s|{{CODE_SMELLS}}|${CODE_SMELLS}|g" \
    -e
