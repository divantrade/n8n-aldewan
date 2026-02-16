#!/usr/bin/env bash
# pull.sh - سحب workflows من n8n وحفظها محلياً
# الاستخدام:
#   ./scripts/pull.sh            # سحب جميع workflows
#   ./scripts/pull.sh 42         # سحب workflow محدد بالـ ID
#   ./scripts/pull.sh --active   # سحب workflows المفعّلة فقط

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

# التحقق من المتطلبات
if [ -z "${N8N_URL:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
    echo "خطأ: N8N_URL و N8N_API_KEY مطلوبان في .env"
    exit 1
fi

# التحقق من وجود jq
if ! command -v jq &> /dev/null; then
    echo "خطأ: jq مطلوب. قم بتثبيته:"
    echo "  Ubuntu/Debian: sudo apt install jq"
    echo "  macOS: brew install jq"
    exit 1
fi

# إزالة / الزائدة من URL
N8N_URL="${N8N_URL%/}"

mkdir -p "$WORKFLOWS_DIR"

# دالة لتنظيف اسم الملف
sanitize_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# دالة لسحب workflow واحد
pull_workflow() {
    local workflow_id="$1"

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        -H "Accept: application/json" \
        "$N8N_URL/api/v1/workflows/$workflow_id")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        echo "  خطأ: فشل سحب workflow #$workflow_id (HTTP $http_code)"
        return 1
    fi

    local name
    name=$(echo "$body" | jq -r '.name // "unnamed"')
    local safe_name
    safe_name=$(sanitize_name "$name")
    local filename="${workflow_id}_${safe_name}.json"

    # حفظ الـ workflow بتنسيق مرتب
    echo "$body" | jq '.' > "$WORKFLOWS_DIR/$filename"
    echo "  تم سحب: $filename ($name)"
}

# سحب workflow محدد
if [ "${1:-}" != "" ] && [ "${1:-}" != "--active" ]; then
    echo "سحب workflow #$1 من $N8N_URL ..."
    pull_workflow "$1"
    echo "تم!"
    exit 0
fi

# بناء URL الطلب
API_URL="$N8N_URL/api/v1/workflows?limit=250"
if [ "${1:-}" = "--active" ]; then
    API_URL="$API_URL&active=true"
    echo "سحب workflows المفعّلة من $N8N_URL ..."
else
    echo "سحب جميع workflows من $N8N_URL ..."
fi

# جلب قائمة الـ workflows
response=$(curl -s -w "\n%{http_code}" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Accept: application/json" \
    "$API_URL")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" != "200" ]; then
    echo "خطأ: فشل الاتصال بـ n8n (HTTP $http_code)"
    echo "$body" | jq '.' 2>/dev/null || echo "$body"
    exit 1
fi

# استخراج IDs وسحب كل workflow
workflow_ids=$(echo "$body" | jq -r '.data[].id')
count=$(echo "$workflow_ids" | grep -c . || echo 0)

echo "وُجدت $count workflow(s)"
echo ""

for id in $workflow_ids; do
    pull_workflow "$id"
done

echo ""
echo "تم سحب جميع workflows إلى: $WORKFLOWS_DIR"
echo "عدد الملفات: $(ls -1 "$WORKFLOWS_DIR"/*.json 2>/dev/null | wc -l)"
