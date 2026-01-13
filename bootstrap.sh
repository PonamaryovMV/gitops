#!/usr/bin/env bash
set -e

APPS=(
  pifagor2-onboarding
  pifagor2-web
  pifagor2-api
)

ENVS=(dev uat prod)

echo "📁 Bootstrapping GitOps repo in current directory..."

mkdir -p applicationsets projects apps helm-charts

# -------------------------
# Helm main chart
# -------------------------
MAIN_CHART=helm-charts/main/0.0.1
mkdir -p $MAIN_CHART/templates

cat > $MAIN_CHART/Chart.yaml <<EOF
apiVersion: v2
name: main
version: 0.0.1
EOF

cat > $MAIN_CHART/values.yaml <<EOF
image:
  repository: alpine
  tag: "3.19"
  pullPolicy: IfNotPresent

command:
  - sleep
  - "3600"
EOF

cat > $MAIN_CHART/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: {{ toYaml .Values.command | nindent 12 }}
EOF

# -------------------------
# Applications
# -------------------------
for APP in "${APPS[@]}"; do
  echo "📦 Creating app $APP"

  APP_DIR=apps/$APP
  mkdir -p $APP_DIR/values

  cat > $APP_DIR/Chart.yaml <<EOF
apiVersion: v2
name: $APP
version: 0.1.0
appVersion: "0.1.0"

dependencies:
  - name: main
    version: 0.0.1
    repository: "file://../../helm-charts/main/0.0.1"
EOF

  for ENV in "${ENVS[@]}"; do
    cat > $APP_DIR/values/$ENV.yaml <<EOF
image:
  repository: alpine
  tag: "3.19"

env: $ENV
EOF
  done

  cat > $APP_DIR/README.md <<EOF
# $APP

Test application for Argo CD GitOps bootstrap.
EOF

done

# -------------------------
# AppProject
# -------------------------
cat > projects/default.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
EOF

# -------------------------
# ApplicationSet
# -------------------------
cat > applicationsets/apps.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://REPLACE_ME/infra-gitops.git
        revision: HEAD
        directories:
          - path: apps/*
  template:
    metadata:
      name: '{{path.basename}}-dev'
    spec:
      project: default
      source:
        repoURL: https://REPLACE_ME/infra-gitops.git
        targetRevision: HEAD
        path: '{{path}}'
        helm:
          valueFiles:
            - values/dev.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: dev
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF

cat > README.md <<EOF
# GitOps repository

Bootstrap structure for Argo CD testing.
EOF

echo "✅ Bootstrap completed successfully"
