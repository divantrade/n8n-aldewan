#!/usr/bin/env bash
# sync.sh - مزامنة ثنائية بين المستودع و n8n
# الاستخدام:
#   ./scripts/sync.sh              # مزامنة تفاعلية
#   ./scripts/sync.sh pull         # سحب من n8n
#   ./scripts/sync.sh push         # دفع إلى n8n
#   ./scripts/sync.sh status       # عرض حالة المزامنة
#   ./scripts/sync.sh extract-code # استخراج كود Code nodes من workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$PROJECT_DIR/workflows"
CODE_DIR="$PROJECT_DIR/code-nodes"

# تحميل الإعدادات
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# ألوان للإخراج
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # بدون لون

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  n8n-aldewan Sync Tool${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# استخراج كود Code nodes من ملفات workflow JSON
extract_code_nodes() {
    mkdir -p "$CODE_DIR"

    if [ ! -d "$WORKFLOWS_DIR" ] || [ -z "$(ls -A "$WORKFLOWS_DIR"/*.json 2>/dev/null)" ]; then
        echo "لا توجد workflows لاستخراج الكود منها"
        echo "قم بتشغيل: ./scripts/sync.sh pull"
        return 1
    fi

    echo -e "${BLUE}استخراج Code nodes من workflows ...${NC}"
    echo ""

    local total=0
    for filepath in "$WORKFLOWS_DIR"/*.json; do
        local filename
        filename=$(basename "$filepath")
        local workflow_id
        workflow_id=$(echo "$filename" | grep -oP '^\d+' || echo "unknown")
        local workflow_name
        workflow_name=$(jq -r '.name // "unnamed"' "$filepath")

        # البحث عن Code nodes
        local code_nodes
        code_nodes=$(jq -r '.nodes[] | select(.type == "n8n-nodes-base.code") | .name' "$filepath" 2>/dev/null || echo "")

        if [ -z "$code_nodes" ]; then
            continue
        fi

        local safe_wf_name
        safe_wf_name=$(echo "$workflow_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
        local wf_dir="$CODE_DIR/${workflow_id}_${safe_wf_name}"
        mkdir -p "$wf_dir"

        while IFS= read -r node_name; do
            local safe_node_name
            safe_node_name=$(echo "$node_name" | sed 's/[^a-zA-Z0-9._-]/_/g')

            # استخراج الكود (jsCode أو pythonCode)
            local js_code
            js_code=$(jq -r --arg name "$node_name" '.nodes[] | select(.name == $name) | .parameters.jsCode // empty' "$filepath")
            local py_code
            py_code=$(jq -r --arg name "$node_name" '.nodes[] | select(.name == $name) | .parameters.pythonCode // empty' "$filepath")

            if [ -n "$js_code" ]; then
                echo "$js_code" > "$wf_dir/${safe_node_name}.js"
                echo -e "  ${GREEN}+${NC} $workflow_name / $node_name -> .js"
                total=$((total + 1))
            fi
            if [ -n "$py_code" ]; then
                echo "$py_code" > "$wf_dir/${safe_node_name}.py"
                echo -e "  ${GREEN}+${NC} $workflow_name / $node_name -> .py"
                total=$((total + 1))
            fi
        done <<< "$code_nodes"
    done

    echo ""
    echo -e "${GREEN}تم استخراج $total code node(s) إلى: $CODE_DIR${NC}"
}

# إعادة حقن الكود المعدّل إلى ملفات workflow JSON
inject_code_nodes() {
    if [ ! -d "$CODE_DIR" ]; then
        echo "لا يوجد مجلد code-nodes. قم بتشغيل extract-code أولاً."
        return 1
    fi

    echo -e "${BLUE}إعادة حقن Code nodes في workflows ...${NC}"
    echo ""

    local total=0
    for wf_dir in "$CODE_DIR"/*/; do
        [ -d "$wf_dir" ] || continue

        local dir_name
        dir_name=$(basename "$wf_dir")
        local workflow_id
        workflow_id=$(echo "$dir_name" | grep -oP '^\d+' || echo "")

        if [ -z "$workflow_id" ]; then
            continue
        fi

        # البحث عن ملف workflow المقابل
        local wf_file
        wf_file=$(ls "$WORKFLOWS_DIR"/${workflow_id}_*.json 2>/dev/null | head -1)

        if [ -z "$wf_file" ]; then
            echo -e "  ${YELLOW}تحذير: لا يوجد workflow file لـ ID $workflow_id${NC}"
            continue
        fi

        for code_file in "$wf_dir"/*.js "$wf_dir"/*.py; do
            [ -f "$code_file" ] || continue

            local code_filename
            code_filename=$(basename "$code_file")
            local node_name
            node_name="${code_filename%.*}"
            # إعادة تحويل _ إلى أحرف أصلية (تقريبي)
            local ext="${code_filename##*.}"

            local code_content
            code_content=$(cat "$code_file")

            local param_name="jsCode"
            if [ "$ext" = "py" ]; then
                param_name="pythonCode"
            fi

            # تحديث الكود في ملف JSON
            local tmp_file
            tmp_file=$(mktemp)
            jq --arg name "$node_name" --arg code "$code_content" --arg param "$param_name" \
                '(.nodes[] | select(.name == $name) | .parameters[$param]) = $code' \
                "$wf_file" > "$tmp_file" && mv "$tmp_file" "$wf_file"

            echo -e "  ${GREEN}*${NC} حُقن: $code_filename -> $(basename "$wf_file")"
            total=$((total + 1))
        done
    done

    echo ""
    echo -e "${GREEN}تم حقن $total code node(s)${NC}"
}

# عرض حالة المزامنة
show_status() {
    echo -e "${BLUE}حالة المزامنة:${NC}"
    echo ""

    # عرض إعدادات الاتصال
    if [ -n "${N8N_URL:-}" ]; then
        echo -e "  n8n URL: ${GREEN}$N8N_URL${NC}"
        echo -e "  API Key: ${GREEN}مُعدّ${NC}"
    else
        echo -e "  n8n URL: ${RED}غير مُعدّ${NC}"
        echo -e "  أنشئ ملف .env أولاً"
    fi
    echo ""

    # عرض workflows المحلية
    local local_count=0
    if [ -d "$WORKFLOWS_DIR" ]; then
        local_count=$(ls -1 "$WORKFLOWS_DIR"/*.json 2>/dev/null | wc -l || echo 0)
    fi
    echo -e "  Workflows محلية: ${YELLOW}$local_count${NC}"

    if [ "$local_count" -gt 0 ]; then
        echo ""
        for f in "$WORKFLOWS_DIR"/*.json; do
            local name
            name=$(jq -r '.name // "unnamed"' "$f")
            local id
            id=$(jq -r '.id // "?"' "$f")
            local active
            active=$(jq -r '.active // false' "$f")
            local status_icon="○"
            [ "$active" = "true" ] && status_icon="●"
            echo "    $status_icon #$id: $name"
        done
    fi

    # عرض code nodes المستخرجة
    echo ""
    local code_count=0
    if [ -d "$CODE_DIR" ]; then
        code_count=$(find "$CODE_DIR" -name "*.js" -o -name "*.py" 2>/dev/null | wc -l || echo 0)
    fi
    echo -e "  Code nodes مستخرجة: ${YELLOW}$code_count${NC}"

    echo ""
    echo -e "  آخر git commit: $(git -C "$PROJECT_DIR" log -1 --format='%h %s' 2>/dev/null || echo 'لا يوجد')"
}

# القائمة الرئيسية
case "${1:-}" in
    pull)
        "$SCRIPT_DIR/pull.sh" "${@:2}"
        ;;
    push)
        # حقن الكود أولاً إذا كان هناك code nodes معدّلة
        if [ -d "$CODE_DIR" ]; then
            inject_code_nodes
        fi
        "$SCRIPT_DIR/push.sh" "${@:2}"
        ;;
    status)
        print_header
        show_status
        ;;
    extract-code)
        extract_code_nodes
        ;;
    inject-code)
        inject_code_nodes
        ;;
    "")
        print_header
        show_status
        echo ""
        echo -e "${YELLOW}الأوامر المتاحة:${NC}"
        echo "  ./scripts/sync.sh pull          سحب workflows من n8n"
        echo "  ./scripts/sync.sh push          دفع workflows إلى n8n"
        echo "  ./scripts/sync.sh status        عرض حالة المزامنة"
        echo "  ./scripts/sync.sh extract-code  استخراج Code nodes كملفات منفصلة"
        echo "  ./scripts/sync.sh inject-code   إعادة حقن الكود المعدّل في workflows"
        echo ""
        echo -e "${YELLOW}طريقة العمل المقترحة:${NC}"
        echo "  1. sync.sh pull          # سحب workflows من n8n"
        echo "  2. sync.sh extract-code  # استخراج الكود لملفات منفصلة"
        echo "  3. عدّل الكود في code-nodes/"
        echo "  4. sync.sh push          # دفع التعديلات (يحقن الكود تلقائياً)"
        echo "  5. git add . && git commit  # حفظ في Git"
        ;;
    *)
        echo "أمر غير معروف: $1"
        echo "استخدم: ./scripts/sync.sh [pull|push|status|extract-code|inject-code]"
        exit 1
        ;;
esac
