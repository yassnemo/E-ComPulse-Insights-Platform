{{/*
Expand the name of the chart.
*/}}
{{- define "ecompulse-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ecompulse-platform.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ecompulse-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ecompulse-platform.labels" -}}
helm.sh/chart: {{ include "ecompulse-platform.chart" . }}
{{ include "ecompulse-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ecompulse-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ecompulse-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ecompulse-platform.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ecompulse-platform.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "ecompulse-platform.annotations" -}}
app.kubernetes.io/component: {{ .component | default "application" }}
app.kubernetes.io/part-of: ecompulse-platform
environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Image pull policy
*/}}
{{- define "ecompulse-platform.imagePullPolicy" -}}
{{- if .Values.global.environment | eq "development" }}
Always
{{- else }}
IfNotPresent
{{- end }}
{{- end }}

{{/*
Resource limits helper
*/}}
{{- define "ecompulse-platform.resources" -}}
{{- if .resources }}
resources:
  {{- if .resources.requests }}
  requests:
    {{- if .resources.requests.memory }}
    memory: {{ .resources.requests.memory }}
    {{- end }}
    {{- if .resources.requests.cpu }}
    cpu: {{ .resources.requests.cpu }}
    {{- end }}
  {{- end }}
  {{- if .resources.limits }}
  limits:
    {{- if .resources.limits.memory }}
    memory: {{ .resources.limits.memory }}
    {{- end }}
    {{- if .resources.limits.cpu }}
    cpu: {{ .resources.limits.cpu }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Security context helper
*/}}
{{- define "ecompulse-platform.securityContext" -}}
securityContext:
  {{- if .Values.securityContext.runAsNonRoot }}
  runAsNonRoot: {{ .Values.securityContext.runAsNonRoot }}
  {{- end }}
  {{- if .Values.securityContext.runAsUser }}
  runAsUser: {{ .Values.securityContext.runAsUser }}
  {{- end }}
  {{- if .Values.securityContext.fsGroup }}
  fsGroup: {{ .Values.securityContext.fsGroup }}
  {{- end }}
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
{{- end }}

{{/*
Pod security context helper
*/}}
{{- define "ecompulse-platform.podSecurityContext" -}}
securityContext:
  {{- if .Values.podSecurityContext.fsGroup }}
  fsGroup: {{ .Values.podSecurityContext.fsGroup }}
  {{- end }}
  runAsNonRoot: true
  runAsUser: 1000
{{- end }}
