{{/* The release name IS the service name, e.g. "catalog-service". */}}
{{- define "ms.name" -}}
{{ .Release.Name }}
{{- end }}

{{- define "ms.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}

{{- define "ms.labels" -}}
{{ include "ms.selectorLabels" . }}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/part-of: mern-shop
app.kubernetes.io/managed-by: {{ .Release.Service }}
cloud: {{ .Values.global.cloud | quote }}
{{- end }}

{{- define "ms.image" -}}
{{ required "global.imageRegistry is required" .Values.global.imageRegistry }}/{{ .Release.Name }}:{{ required "image.tag is required (--set image.tag=...)" .Values.image.tag }}
{{- end }}
