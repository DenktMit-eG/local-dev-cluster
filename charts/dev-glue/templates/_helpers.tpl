{{- define "dev-glue.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dev-glue.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dev-glue.labels" -}}
helm.sh/chart: {{ include "dev-glue.chart" . }}
{{ include "dev-glue.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "dev-glue.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dev-glue.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
