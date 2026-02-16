# n8n-aldewan

نظام مزامنة ثنائي الاتجاه بين هذا المستودع و n8n instance.
يسمح لك بتعديل workflows و Code nodes محلياً ودفعها لـ n8n، أو سحب التعديلات من n8n.

## الإعداد السريع

```bash
# 1. انسخ ملف الإعدادات وأضف بياناتك
cp .env.example .env
# عدّل .env وأضف N8N_URL و N8N_API_KEY

# 2. اسحب workflows من n8n
./scripts/sync.sh pull

# 3. استخرج Code nodes كملفات منفصلة للتعديل
./scripts/sync.sh extract-code
```

## طريقة العمل

```
┌─────────────┐     pull      ┌─────────────┐
│   n8n       │ ──────────>   │  المستودع   │
│  instance   │               │   (Git)     │
│             │  <──────────  │             │
└─────────────┘     push      └─────────────┘
```

### الأوامر

| الأمر | الوصف |
|-------|-------|
| `./scripts/sync.sh pull` | سحب جميع workflows من n8n |
| `./scripts/sync.sh push` | دفع workflows إلى n8n (يحقن الكود تلقائياً) |
| `./scripts/sync.sh status` | عرض حالة المزامنة |
| `./scripts/sync.sh extract-code` | استخراج Code nodes كملفات .js/.py |
| `./scripts/sync.sh inject-code` | إعادة حقن الكود المعدّل في JSON |
| `./scripts/pull.sh 42` | سحب workflow محدد بالـ ID |
| `./scripts/push.sh workflows/42_*.json` | دفع workflow محدد |

### دورة العمل اليومية

```bash
# 1. سحب آخر التعديلات من n8n
./scripts/sync.sh pull

# 2. استخراج الكود للتعديل
./scripts/sync.sh extract-code

# 3. عدّل الكود في مجلد code-nodes/
#    (يمكنك استخدام أي محرر أو Claude)

# 4. دفع التعديلات لـ n8n
./scripts/sync.sh push

# 5. حفظ في Git
git add .
git commit -m "تحديث workflow الدعم"
```

## هيكل المشروع

```
n8n-aldewan/
├── .env.example          # قالب الإعدادات
├── .env                  # إعداداتك (غير محفوظ في Git)
├── .gitignore
├── README.md
├── workflows/            # ملفات workflow JSON كاملة
│   ├── 1_My_Workflow.json
│   └── 2_Support_Bot.json
├── code-nodes/           # كود Code nodes مستخرج
│   ├── 1_My_Workflow/
│   │   └── Process_Events.js
│   └── 2_Support_Bot/
│       └── Handle_Messages.js
└── scripts/
    ├── pull.sh           # سحب من n8n
    ├── push.sh           # دفع إلى n8n
    └── sync.sh           # أداة المزامنة الرئيسية
```

## المتطلبات

- `bash` 4+
- `curl`
- `jq` - لمعالجة JSON (`sudo apt install jq` أو `brew install jq`)
- n8n API Key (من Settings > API في n8n)
