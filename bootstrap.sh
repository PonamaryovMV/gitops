#!/bin/bash
set -e

echo "==> Стартируем bootstrap репозитория GitOps"

# Определяем корень репозитория
REPO_ROOT="$(pwd)"

# Папки
APPS_DIR="${REPO_ROOT}/apps"
HELM_DIR="${REPO_ROOT}/helm-charts"
PROJECTS_DIR="${REPO_ROOT}/projects"

# Список приложений и окружений
APPLICATIONS=("pifagor2-api" "pifagor2-web" "pifagor2-onboarding")
ENVS=("dev" "uat" "prod")

# Создаём базовые директории
mkdir -p "${APPS_DIR}" "${HELM_DIR}/main/0.0.1/templates" "${PROJECTS_DIR}"

# Создаём dummy main chart
cat > "${HELM_DIR}/main/0.0.1/Chart.yaml" <<EOF
apiVersion: v2
name: main
version: 0.0.1
appVersion: "0.0.1"
EOF

# Пустой deployment.yaml для main chart
cat > "${HELM_DIR}/main/0.0.1/templates/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dummy-main
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dummy-main
  template:
    metadata:
      labels:
        app: dummy-main
    spec:
      containers:
      - name: dummy
        image: alpine:3.18
        command: ["sh", "-c", "sleep 3600"]
EOF

# Пустые values.yaml для main chart
echo "{}" > "${HELM_DIR}/main/0.0.1/values.yaml"

# Создаём проекты
cat > "${PROJECTS_DIR}/default.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Default project
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: '*'
EOF

# Создаём приложения
for app in "${APPLICATIONS[@]}"; do
  APP_DIR="${APPS_DIR}/${app}"
  mkdir -p "${APP_DIR}/values" "${APP_DIR}/charts/main/0.0.1/templates"

  # README.md
  echo "# ${app}" > "${APP_DIR}/README.md"

  # Chart.yaml wrapper chart
  cat > "${APP_DIR}/Chart.yaml" <<EOF
apiVersion: v2
name: ${app}
version: 0.1.0
appVersion: "0.1.0"

dependencies:
  - name: main
    version: 0.0.1
    repository: "file://charts/main/0.0.1"
EOF

  # Копируем dummy main chart внутрь приложения
  cp -r "${HELM_DIR}/main/0.0.1/." "${APP_DIR}/charts/main/0.0.1/"

  # Создаём пустые values для окружений
  for env in "${ENVS[@]}"; do
    echo "# Values for ${app} in ${env}" > "${APP_DIR}/values/${env}.yaml"
  done
done

# Создаём ApplicationSet папку с пустым примером
mkdir -p "${REPO_ROOT}/applicationsets"
cat > "${REPO_ROOT}/applicationsets/apps.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
          - env: uat
          - env: prod
  template:
    metadata:
      name: '{{path.basename}}-{{env}}'
    spec:
      project: default
      source:
        repoURL: <REPO_URL>
        targetRevision: main
        path: apps/{{path.basename}}
        helm:
          valueFiles:
            - values/{{env}}.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}-{{env}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF

echo "==> Bootstrap репозитория завершён! Структура готова для ArgoCD"
