#!/bin/bash
set -e

########################################
# CONFIGURATION
########################################

SONAR_URL="http://localhost:9000"
PROJECT_KEY="Multitier"
SONAR_TOKEN="PUT_YOUR_SONAR_TOKEN_HERE"

OUTPUT_DIR="sonar-report"
HTML_REPORT="${OUTPUT_DIR}/sonar-report.html"
JSON_REPORT="${OUTPUT_DIR}/sonar-report.json"
PDF_REPORT="${OUTPUT_DIR}/sonar-report.pdf"

########################################
# PREPARE
########################################

echo "Preparing SonarQube report directory..."
mkdir -p ${OUTPUT_DIR}

########################################
# FETCH DATA FROM SONARQUBE
########################################

echo "Fetching issues from SonarQube..."

curl -s -u ${SONAR_TOKEN}: \
"${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&ps=500" \
-o ${JSON_REPORT}

########################################
# GENERATE HTML REPORT
########################################

echo "Generating HTML report..."

cat <<EOF > ${HTML_REPORT}
<!DOCTYPE html>
<html>
<head>
  <title>SonarQube Report - ${PROJECT_KEY}</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f5f5f5; }
    h1 { background: #4CAF50; color: white; padding: 10px; }
    pre { background: white; padding: 15px; border-radius: 5px; }
  </style>
</head>
<body>

<h1>SonarQube Scan Report</h1>
<p><strong>Project:</strong> ${PROJECT_KEY}</p>
<p><strong>Generated On:</strong> $(date)</p>

<h2>Raw Issues (JSON)</h2>
<pre>
$(cat ${JSON_REPORT})
</pre>

</body>
</html>
EOF

echo "HTML report generated: ${HTML_REPORT}"

########################################
# OPTIONAL: GENERATE PDF (if tool exists)
########################################

if command -v wkhtmltopdf >/dev/null 2>&1; then
  echo "Generating PDF report..."
  wkhtmltopdf ${HTML_REPORT} ${PDF_REPORT}
  echo "PDF report generated: ${PDF_REPORT}"
else
  echo "wkhtmltopdf not installed. Skipping PDF generation."
fi

########################################
# DONE
########################################

echo "SonarQube report generation completed successfully."
