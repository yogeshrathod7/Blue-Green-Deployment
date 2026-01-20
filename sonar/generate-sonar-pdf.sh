#!/bin/bash
set -e

############################################
# CONFIGURATION
############################################
SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"
QUALITY_GATE="ERROR"

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
# METRICS
############################################
TOTAL_ISSUES=$(jq '.total' ${JSON_OUTPUT})
BUGS=$(jq '[.issues[] | select(.type=="BUG")] | length' ${JSON_OUTPUT})
VULNS=$(jq '[.issues[] | select(.type=="VULNERABILITY")] | length' ${JSON_OUTPUT})
CODE_SMELLS=$(jq '[.issues[] | select(.type=="CODE_SMELL")] | length' ${JSON_OUTPUT})

############################################
# GENERATE BASE HTML (WITHOUT ISSUE ROWS)
############################################
echo "📝 Generating base HTML..."

sed \
  -e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
  -e "s|{{ENVIRONMENT}}|${ENVIRONMENT}|g" \
  -e "s|{{GENERATED_DATE}}|$(date)|g" \
  -e "s|{{QUALITY_GATE}}|${QUALITY_GATE}|g" \
  -e "s|{{TOTAL_ISSUES}}|${TOTAL_ISSUES}|g" \
  -e "s|{{BUGS}}|${BUGS}|g" \
  -e "s|{{VULNERABILITIES}}|${VULNS}|g" \
  -e "s|{{CODE_SMELLS}}|${CODE_SMELLS}|g" \
  -e "s|{{ISSUE_ROWS}}||g" \
  ${TEMPLATE_FILE} > ${HTML_OUTPUT}

############################################
# INSERT ISSUE ROWS SAFELY (LINE BY LINE)
############################################
echo "🧩 Inserting issue rows..."

jq -r '
  .issues[] |
  "<tr>" +
  "<td>" + .type + "</td>" +
  "<td class=\"severity-" + .severity + "\">" + .severity + "</td>" +
  "<td>" + .component + "</td>" +
  "<td>" + ((.line | tostring) // "NA") + "</td>" +
  "<td>" + .message + "</td>" +
  "</tr>"
' ${JSON_OUTPUT} >> ${HTML_OUTPUT}

############################################
# CONVERT HTML → PDF
############################################
echo "📄 Converting HTML to PDF..."
wkhtmltopdf ${HTML_OUTPUT} ${PDF_OUTPUT}

############################################
# FINAL CHECK
############################################
echo "✅ SonarQube Executive PDF generated successfully:"
ls -lh ${PDF_OUTPUT}
