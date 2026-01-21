#!/bin/bash
set -e

SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse --short HEAD)

WORKDIR="sonar-report-work"
ISSUES_JSON="${WORKDIR}/issues.json"
HTML_OUT="sonar-report.html"
PDF_OUT="sonar-report.pdf"
TEMPLATE="sonar/sonar-executive-report.html"

PAGE_SIZE=200
MAX_PAGES=5

grade() {
  case "$1" in
    1) echo "A" ;;
    2) echo "B" ;;
    3) echo "C" ;;
    4) echo "D" ;;
    5) echo "E" ;;
    *) echo "A" ;;
  esac
}

rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}
echo '[]' > ${ISSUES_JSON}

echo "Fetching SonarQube issues..."
for ((PAGE=1; PAGE<=MAX_PAGES; PAGE++)); do
  RESP=$(curl -s -u ${SONAR_TOKEN}: \
  "${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&p=${PAGE}&ps=${PAGE_SIZE}")

  COUNT=$(echo "$RESP" | jq '.issues | length')
  [ "$COUNT" -eq 0 ] && break

  jq -s '.[0] + .[1]' \
    ${ISSUES_JSON} <(echo "$RESP" | jq '.issues') \
    > ${ISSUES_JSON}.tmp && mv ${ISSUES_JSON}.tmp ${ISSUES_JSON}
done

# Remove report files from issues
jq '[.[] | select(
  (.component | contains("/sonar/") | not) and
  (.component | contains("sonar-report") | not)
)]' ${ISSUES_JSON} > ${ISSUES_JSON}.tmp && mv ${ISSUES_JSON}.tmp ${ISSUES_JSON}

TOTAL_ISSUES=$(jq 'length' ${ISSUES_JSON})
CRITICAL_ISSUES=$(jq '[.[]|select(.severity=="CRITICAL")]|length' ${ISSUES_JSON})
MAJOR_ISSUES=$(jq '[.[]|select(.severity=="MAJOR")]|length' ${ISSUES_JSON})
VULNERABILITIES=$(jq '[.[]|select(.type=="VULNERABILITY")]|length' ${ISSUES_JSON})

RATINGS=$(curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/measures/component?component=${PROJECT_KEY}&metricKeys=reliability_rating,security_rating,sqale_rating")

RELIABILITY_GRADE=$(grade "$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="reliability_rating")|.value')")
SECURITY_GRADE=$(grade "$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="security_rating")|.value')")
MAINTAINABILITY_GRADE=$(grade "$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="sqale_rating")|.value')")

if [ "$CRITICAL_ISSUES" -gt 0 ]; then
  QUALITY_GATE="FAILED"
  FINAL_DECISION="NOT APPROVED FOR PRODUCTION"
  QG_CLASS="fail"
else
  QUALITY_GATE="PASSED"
  FINAL_DECISION="APPROVED FOR PRODUCTION"
  QG_CLASS="pass"
fi

sed \
-e "s|{{PROJECT_NAME}}|${PROJECT_KEY}|g" \
-e "s|{{ENVIRONMENT}}|${ENVIRONMENT}|g" \
-e "s|{{BRANCH}}|${BRANCH}|g" \
-e "s|{{COMMIT_ID}}|${COMMIT_ID}|g" \
-e "s|{{GENERATED_DATE}}|$(date)|g" \
-e "s|{{QUALITY_GATE}}|${QUALITY_GATE}|g" \
-e "s|{{QG_CLASS}}|${QG_CLASS}|g" \
-e "s|{{FINAL_DECISION}}|${FINAL_DECISION}|g" \
-e "s|{{TOTAL_ISSUES}}|${TOTAL_ISSUES}|g" \
-e "s|{{CRITICAL_ISSUES}}|${CRITICAL_ISSUES}|g" \
-e "s|{{MAJOR_ISSUES}}|${MAJOR_ISSUES}|g" \
-e "s|{{VULNERABILITIES}}|${VULNERABILITIES}|g" \
-e "s|{{RELIABILITY_GRADE}}|${RELIABILITY_GRADE}|g" \
-e "s|{{SECURITY_GRADE}}|${SECURITY_GRADE}|g" \
-e "s|{{MAINTAINABILITY_GRADE}}|${MAINTAINABILITY_GRADE}|g" \
-e "s|{{ISSUE_ROWS}}||g" \
${TEMPLATE} > ${HTML_OUT}

jq -r '
.[] |
select(.severity=="CRITICAL" or .severity=="MAJOR") |
"<tr><td>"+.type+"</td>"+
"<td class=\"severity-"+.severity+"\">"+.severity+"</td>"+
"<td>"+(.component|split(":")[-1])+"</td>"+
"<td>"+((.line|tostring)//"-")+"</td>"+
"<td>"+(.message|gsub("\n";" "))+"</td></tr>"
' ${ISSUES_JSON} | head -n 15 >> ${HTML_OUT}

wkhtmltopdf ${HTML_OUT} ${PDF_OUT}

echo "✅ FINAL Production SonarQube PDF generated"
