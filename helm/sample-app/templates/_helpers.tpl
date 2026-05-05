{{- define "nginx-app.fullname" -}}
{{ .Release.Name }}-nginx
{{- end }}