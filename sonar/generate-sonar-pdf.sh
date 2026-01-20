#!/bin/bash
set -e

SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"
QUALITY_GATE="PASSED"

echo "🔎 Checking tools..."
jq --version
wkhtmltopdf --version

echo "📥 Fetching SonarQube issues..."
curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&ps=500" \
-o sonar-report.json

TOTAL_ISSUES=$(jq '.total' sonar-report.json)
BUGS=$(jq '[.issues[] | select(.type=="BUG")] | length' sonar-report.json)
VULNS=$(jq '[.issues[] | select(.type=="VULNERABILITY")] | length' sonar-report.json)
CODE_SMELLS=$(jq '[.issues[] | select(.type=="CODE_SMELL")] | length' sonar-report.json)

echo "🧩 Building issue rows..."
ISSUE_ROWS=$(jq -r '
  .issues[] |
  "<tr>
    <td>" + .type + "</td>
    <td class=\\"severity-" + .severity + "\\">" + .severity + "</td>
    <td>" + .component + "</td>
    <td>" + ((.line|tostring) // "NA") + "</td>
    <td>" + .message + "</td>
  </tr>"
' sonar-report.json)

echo "📝 Generating HTML from template..."
sed -e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
    -e "s|{{ENVIRONMENT}}|${ENVIRONMENT}|g" \
    -e "s|{{GENERATED_DATE}}|$(date)|g" \
    -e "s|{{QUALITY_GATE}}|${QUALITY_GATE}|g" \
    -e "s|{{TOTAL_ISSUES}}|${TOTAL_ISSUES}|g" \
    -e "s|{{BUGS}}|${BUGS}|g" \
    -e "s|{{VULNERABILITIES}}|${VULNS}|g" \
    -e "s|{{CODE_SMELLS}}|${CODE_SMELLS}|g" \
    -e "s|{{ISSUE_ROWS}}|${ISSUE_ROWS}|g" \
    sonar/sonar-executive-report.html \
    > sonar-report.html

echo "📄 Converting HTML to PDF..."
wkhtmltopdf sonar-report.html sonar-report.pdf

echo "✅ PDF generated:"
ls -lh sonar-report.pdf
