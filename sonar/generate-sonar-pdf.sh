#!/bin/bash
set -e

SONAR_URL="http://98.94.90.125:9000"
PROJECT_KEY="Multitier"
ENVIRONMENT="PRODUCTION"

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse --short HEAD)

WORKDIR="sonar-report-work"
ISSUES_JSON="${WORKDIR}/issues.json"
HTML_OUT="sonar-report.html"
PDF_OUT="sonar-report.pdf"
TEMPLATE="sonar/sonar-executive-report.html"

PAGE_SIZE=200
MAX_PAGES=5

echo "Preparing SonarQube report directory..."
rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}
echo "[]">${ISSUES_JSON}

echo "Checking required tools..."
jq --version
wkhtmltopdf --version

###################################
# FETCH ISSUES
###################################
echo "Fetching issues from SonarQube..."

for ((PAGE=1; PAGE<=MAX_PAGES; PAGE++)); do
  RESP=$(curl --connect-timeout 10 --max-time 60 -s -u ${SONAR_TOKEN}: \
  "${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&p=${PAGE}&ps=${PAGE_SIZE}")

  COUNT=$(echo "$RESP" | jq '.issues | length')
  [ "$COUNT" -eq 0 ] && break

  jq -s '.[0] + .[1]' \
    ${ISSUES_JSON} <(echo "$RESP" | jq '.issues') \
    > ${ISSUES_JSON}.tmp && mv ${ISSUES_JSON}.tmp ${ISSUES_JSON}
done

###################################
# METRICS
###################################
TOTAL_ISSUES=$(jq 'length' ${ISSUES_JSON})
BUGS=$(jq '[.[]|select(.type=="BUG")]|length' ${ISSUES_JSON})
VULNERABILITIES=$(jq '[.[]|select(.type=="VULNERABILITY")]|length' ${ISSUES_JSON})
CODE_SMELLS=$(jq '[.[]|select(.type=="CODE_SMELL")]|length' ${ISSUES_JSON})

###################################
# RATINGS
###################################
RATINGS=$(curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/measures/component?component=${PROJECT_KEY}&metricKeys=reliability_rating,security_rating,sqale_rating")

RELIABILITY=$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="reliability_rating")|.value')
SECURITY_RATING=$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="security_rating")|.value')
MAINTAINABILITY=$(echo "$RATINGS" | jq -r '.component.measures[]|select(.metric=="sqale_rating")|.value')

###################################
# QUALITY GATE
###################################
if [ "$VULNERABILITIES" -gt 0 ]; then
  QUALITY_GATE="FAILED"
  QG_CLASS="fail"
else
  QUALITY_GATE="PASSED"
  QG_CLASS="pass"
fi

###################################
# BASE HTML
###################################
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
-e "s|{{CODE_SMELLS}}|${CODE_SMELLS}|g" \
-e "s|{{RELIABILITY}}|${RELIABILITY}|g" \
-e "s|{{SECURITY_RATING}}|${SECURITY_RATING}|g" \
-e "s|{{MAINTAINABILITY}}|${MAINTAINABILITY}|g" \
-e "s|{{ISSUE_ROWS}}||g" \
${TEMPLATE} > ${HTML_OUT}

###################################
# ISSUE ROWS (TOP 20)
###################################
jq -r '
.[] |
select(.severity=="CRITICAL" or .severity=="MAJOR") |
"<tr><td>"+.type+"</td>"+
"<td class=\"severity-"+.severity+"\">"+.severity+"</td>"+
"<td>"+(.component|split(":")[-1])+"</td>"+
"<td>"+((.line|tostring)//"-")+"</td>"+
"<td>"+.message+"</td></tr>"
' ${ISSUES_JSON} | head -n 20 >> ${HTML_OUT}

###################################
# PDF
###################################
wkhtmltopdf ${HTML_OUT} ${PDF_OUT}

echo "✅ Production SonarQube PDF generated successfully"
ls -lh ${PDF_OUT}
