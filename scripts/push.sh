#!/usr/bin/env bash
# push.sh - دفع workflows من المستودع إلى n8n
# الاستخدام:
#   ./scripts/push.sh                     # دفع جميع workflows
#   ./scripts/push.sh workflows/42_*.json # دفع workflow محدد
#   ./scripts/push.sh --dry-run           # عرض ما سيتم دفعه فقط

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$PROJECT_DIR/workflows"

# تحميل الإعدادات
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
else
    echo "خطأ: ملف .env غير موجود"
    echo "قم بنسخ .env.example إلى .env وأضف إعداداتك:"
    echo "  cp .env.example .env"
    exit 1
fi

if [ -z "${N8N_URL:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
    echo "خطأ: N8N_URL و N8N_API_KEY مطلوبان في .env"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "خطأ: jq مطلوب"
    exit 1
fi

N8N_URL="${N8N_URL%/}"
DRY_RUN=false

# معالجة المعاملات
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    shift
fi

# دالة لدفع workflow واحد
push_workflow() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    # استخراج workflow ID من اسم الملف أو من محتوى JSON
    local workflow_id
    workflow_id=$(echo "$filename" | grep -oP '^\d+' || echo "")

    if [ -z "$workflow_id" ]; then
        # محاولة قراءة ID من داخل ملف JSON
        workflow_id=$(jq -r '.id // empty' "$filepath")
    fi

    if [ -z "$workflow_id" ]; then
        echo "  تحذير: تجاوز $filename (لا يحتوي على ID)"
        return 0
    fi

    local name
    name=$(jq -r '.name // "unnamed"' "$filepath")

    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] سيتم تحديث: #$workflow_id ($name)"
        return 0
    fi

    # تحضير البيانات للإرسال (إزالة الحقول التي لا يقبلها n8n في التحديث)
    local payload
    payload=$(jq 'del(.id, .createdAt, .updatedAt, .versionId) | {name, nodes, connections, settings, staticData, tags}' "$filepath")

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$N8N_URL/api/v1/workflows/$workflow_id")

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        echo "  تم تحديث: #$workflow_id ($name)"
    else
        local body
        body=$(echo "$response" | sed '$d')
        echo "  خطأ: فشل تحديث #$workflow_id ($name) - HTTP $http_code"
        echo "  $body" | jq -r '.message // .' 2>/dev/null || echo "  $body"
        return 1
    fi
}

# دفع ملف محدد أو جميع الملفات
if [ "${1:-}" != "" ]; then
    # ملف محدد
    if [ ! -f "$1" ]; then
        echo "خطأ: الملف غير موجود: $1"
        exit 1
    fi
    echo "دفع workflow واحد إلى $N8N_URL ..."
    push_workflow "$1"
else
    # جميع الملفات
    if [ ! -d "$WORKFLOWS_DIR" ] || [ -z "$(ls -A "$WORKFLOWS_DIR"/*.json 2>/dev/null)" ]; then
        echo "لا توجد workflows للدفع في $WORKFLOWS_DIR"
        echo "قم بتشغيل pull.sh أولاً لسحب workflows من n8n"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[dry-run] عرض ما سيتم دفعه إلى $N8N_URL ..."
    else
        echo "دفع workflows إلى $N8N_URL ..."
    fi

    errors=0
    count=0
    for filepath in "$WORKFLOWS_DIR"/*.json; do
        count=$((count + 1))
        push_workflow "$filepath" || errors=$((errors + 1))
    done

    echo ""
    echo "النتيجة: $count workflow(s), $errors خطأ"
fi
