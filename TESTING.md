# Odoo 15 Docker - Testing Guide

دليل شامل لاختبار جميع مزايا الـ setup.

## المتطلبات الأولية

- ✅ GitHubSyncer قيد التشغيل
- ✅ odoo-core-addons مسحوب من GitHubSyncer (435 modules)
- ✅ Odoo image تم بناؤه

---

## الاختبار 1️⃣: تشغيل النسخة واستعراض Logs

### تشغيل Containers

```bash
# تأكد أنك في مجلد odoo15-docker
cd odoo15-docker

# شغّل الـ stack
docker compose up -d

# تحقق من حالة الـ containers
docker compose ps
```

### استعراض جميع ملفات الـ Logs

#### 1. Container Logs (stdout/stderr)

```bash
# Odoo logs (real-time)
docker compose logs -f odoo

# Database logs
docker compose logs -f db

# آخر 100 سطر من Odoo
docker compose logs --tail=100 odoo

# جميع الـ logs
docker compose logs
```

#### 2. Odoo Application Log File

```bash
# قراءة ملف الـ log الداخلي
docker compose exec odoo cat /var/lib/odoo/logs/odoo.log

# متابعة الـ log بشكل مباشر
docker compose exec odoo tail -f /var/lib/odoo/logs/odoo.log

# آخر 50 سطر
docker compose exec odoo tail -50 /var/lib/odoo/logs/odoo.log
```

#### 3. Entrypoint Logs

ابحث عن:
- ✅ `[INFO] Odoo 15 Production Container Starting...`
- ✅ `[INFO] Configuration file generated successfully.`
- ✅ `[INFO] Python packages installed successfully.`
- ✅ `[INFO] NPM packages installed successfully.`
- ✅ `[INFO] INITDB_OPTIONS not set, skipping database initialization.`
- ✅ `[INFO] AUTO_UPGRADE is not TRUE...` (أو `Auto-detected database:`)
- ✅ `[INFO] Starting Odoo...`

#### 4. تصدير جميع الـ Logs

```bash
# حفظ جميع الـ logs في ملف
docker compose logs > odoo-full-logs.txt

# حفظ logs مع timestamps
docker compose logs -t > odoo-logs-with-time.txt
```

### ✅ النتائج المتوقعة:

- Containers تعمل بنجاح (Status: Up)
- لا توجد errors في الـ logs
- Odoo يستمع على port 8069
- Database متصلة

---

## الاختبار 2️⃣: إضافة Repository جديد عبر GitHubSyncer

### الخطوة 1: افتح GitHubSyncer UI

```
http://localhost:3000
```

### الخطوة 2: أضف Repository جديد

سنضيف **OCA Website** modules كمثال:

1. اضغط **"Add Repository"**
2. أدخل البيانات:
   ```
   Repository URL: https://github.com/OCA/website
   Branch: 15.0
   Name: oca-website
   ```
3. اضغط **"Save"**
4. اضغط **"Sync Now"**
5. انتظر حتى يكتمل الـ sync

### الخطوة 3: تحقق من الـ Volume

```bash
# شاهد محتويات الـ volume
docker run --rm -v githubsyncer_repo_storage:/data alpine ls -la /data

# تفاصيل المجلدات
docker run --rm -v githubsyncer_repo_storage:/data alpine du -sh /data/*

# شاهد OCA website modules
docker run --rm -v githubsyncer_repo_storage:/data alpine ls -la /data/oca-website
```

### الخطوة 4: إضافة الـ Repo لـ addons_path

عدّل `docker-compose.yml`:

```yaml
conf.addons_path: /opt/odoo/odoo/addons,/mnt/synced-addons/odoo-core-addons,/mnt/synced-addons/oca-website,/mnt/extra-addons
```

أعد تشغيل:

```bash
docker compose restart odoo
docker compose logs -f odoo
```

### ✅ النتائج المتوقعة:

- GitHubSyncer يسحب الـ repo بنجاح
- الـ modules تظهر في `/mnt/synced-addons/oca-website`
- Odoo يعيد التشغيل بدون أخطاء
- الـ modules الجديدة تظهر في Apps menu

---

## الاختبار 3️⃣: Auto-Upgrade Feature

### السيناريو: تحديث module وعمل restart

#### الخطوة 1: إنشاء قاعدة بيانات

1. افتح `http://localhost:8069`
2. أنشئ database جديدة:
   - **Database Name:** `test_upgrade`
   - **Email:** `admin@example.com`
   - **Password:** `admin`
   - **Demo data:** لا

#### الخطوة 2: تثبيت module

1. اذهب إلى **Apps**
2. ابحث عن `sale` أو أي module
3. اضغط **Install**

#### الخطوة 3: تعديل Module (محاكاة تحديث)

```bash
# ادخل للـ container
docker compose exec odoo bash

# انتقل لمجلد module
cd /mnt/synced-addons/odoo-core-addons/sale

# عدّل ملف (إضافة comment بسيط)
echo "# Test auto-upgrade" >> __init__.py

# اخرج من الـ container
exit
```

**ملاحظة:** بما أن الـ volume read-only، سنحاكي بطريقة أخرى:

```bash
# بدلاً من ذلك، نعمل update عبر GitHubSyncer
# في GitHubSyncer UI:
# 1. اذهب لـ odoo-core-addons
# 2. اضغط "Pull Latest"
# 3. انتظر الـ sync
```

#### الخطوة 4: أعد تشغيل Odoo

```bash
docker compose restart odoo
```

#### الخطوة 5: راقب الـ Logs

```bash
docker compose logs -f odoo
```

### ✅ ابحث عن:

```
[INFO] ODOO_DB_NAME not set, auto-detecting Odoo database...
[INFO] Auto-detected database: test_upgrade
[INFO] Running click-odoo-update for database: test_upgrade...
[INFO] Automatic upgrade completed successfully.
```

### ✅ النتائج المتوقعة:

- Auto-upgrade يعمل تلقائياً
- Database يتم اكتشافها تلقائياً
- Modules المتغيرة تُحدّث فقط
- لا توجد errors

---

## الاختبار 4️⃣: Database Auto-Detection

### تجربة 1: بدون ODOO_DB_NAME

```yaml
# في docker-compose.yml - الوضع الحالي
AUTO_UPGRADE: "TRUE"
# ODOO_DB_NAME: ""  # معلّق
```

```bash
docker compose restart odoo
docker compose logs odoo | grep "Auto-detected"
```

**المتوقع:** `[INFO] Auto-detected database: test_upgrade`

### تجربة 2: مع ODOO_DB_NAME محدد

```yaml
AUTO_UPGRADE: "TRUE"
ODOO_DB_NAME: "test_upgrade"
```

```bash
docker compose restart odoo
docker compose logs odoo | grep "Running click-odoo-update"
```

**المتوقع:** `[INFO] Running click-odoo-update for database: test_upgrade...`

### تجربة 3: تعطيل Auto-Upgrade

```yaml
AUTO_UPGRADE: "FALSE"
```

```bash
docker compose restart odoo
docker compose logs odoo | grep "AUTO_UPGRADE"
```

**المتوقع:** `[INFO] AUTO_UPGRADE is not TRUE, skipping automatic upgrade.`

---

## الاختبار 5️⃣: GitHubSyncer Volume Integration

### تحقق من Volume Mount

```bash
# تحقق من الـ mounts
docker compose exec odoo mount | grep synced-addons

# شاهد المحتوى
docker compose exec odoo ls -la /mnt/synced-addons/

# عدد الـ modules في odoo-core-addons
docker compose exec odoo ls -1 /mnt/synced-addons/odoo-core-addons/ | wc -l
```

**المتوقع:** ~435 modules

### تحقق من addons_path

```bash
# اقرأ الـ config المولّد
docker compose exec odoo cat /etc/odoo/erp.conf | grep addons_path
```

**المتوقع:**
```
addons_path = /opt/odoo/odoo/addons,/mnt/synced-addons/odoo-core-addons,/mnt/extra-addons
```

---

## الاختبار 6️⃣: Custom Addons (extra-addons)

### إنشاء Module بسيط

```bash
mkdir -p extra-addons/test_module
```

أنشئ `extra-addons/test_module/__manifest__.py`:

```python
{
    'name': 'Test Module',
    'version': '15.0.1.0.0',
    'category': 'Tools',
    'summary': 'Test custom addon',
    'depends': ['base'],
    'installable': True,
    'application': False,
}
```

أنشئ `extra-addons/test_module/__init__.py`:

```python
# -*- coding: utf-8 -*-
```

### أعد تشغيل وتحقق

```bash
docker compose restart odoo

# تحقق من ظهور المجلد
docker compose exec odoo ls -la /mnt/extra-addons/
```

ثم في Odoo:
1. اذهب لـ **Apps**
2. **Update Apps List**
3. ابحث عن "Test Module"
4. يجب أن يظهر!

---

## الاختبار 7️⃣: Database Initialization (INITDB_OPTIONS)

### تعديل docker-compose.yml

```yaml
INITDB_OPTIONS: "-n test_init -m base,web,sale --unless-initialized"
```

### حذف الـ database القديمة

```bash
# ادخل لـ database container
docker compose exec db psql -U odoo -d postgres

# احذف قواعد البيانات القديمة
DROP DATABASE IF EXISTS test_upgrade;

# اخرج
\q
```

### أعد تشغيل Odoo

```bash
docker compose restart odoo
docker compose logs -f odoo
```

### ✅ ابحث عن:

```
[INFO] Running click-odoo-initdb with options: -n test_init -m base,web,sale --unless-initialized...
[INFO] Database initialization completed successfully.
```

ثم تحقق:
```bash
docker compose exec db psql -U odoo -d postgres -c "\l"
```

**المتوقع:** database `test_init` موجودة!

---

## الاختبار 8️⃣: Package Installation (PY_INSTALL / NPM_INSTALL)

### Python Packages

```yaml
PY_INSTALL: "requests==2.28.0,beautifulsoup4"
```

```bash
# حذف state file لإعادة التثبيت
docker compose exec odoo rm -f /var/lib/odoo/.state/py_install.done

# أعد التشغيل
docker compose restart odoo

# تحقق من التثبيت
docker compose exec odoo pip list | grep -i requests
docker compose exec odoo pip list | grep -i beautifulsoup
```

### NPM Packages

```yaml
NPM_INSTALL: "sass,postcss"
```

```bash
# حذف state file
docker compose exec odoo rm -f /var/lib/odoo/.state/npm_install.done

# أعد التشغيل
docker compose restart odoo

# تحقق
docker compose exec odoo npm list -g --depth=0 | grep sass
```

---

## الاختبار 9️⃣: Healthcheck

```bash
# شاهد حالة الـ health
docker inspect odoo15-app | grep -A 10 Health

# أو
docker compose ps
```

**المتوقع:** Status: `healthy`

### اختبر الـ endpoint

```bash
curl -f http://localhost:8069/web/login
```

**المتوقع:** HTML response بدون error

---

## الاختبار 🔟: User Permissions (PUID/PGID)

### تحقق من User ID

```bash
docker compose exec odoo id odoo
```

**المتوقع:**
```
uid=1000(odoo) gid=1000(odoo) groups=1000(odoo)
```

### تحقق من File Permissions

```bash
docker compose exec odoo ls -la /var/lib/odoo/
docker compose exec odoo ls -la /etc/odoo/erp.conf
```

**المتوقع:** جميع الملفات owned by `odoo:odoo`

---

## ملخص الاختبارات ✅

| # | الاختبار | الحالة |
|---|---------|--------|
| 1 | تشغيل واستعراض Logs | ⬜ |
| 2 | إضافة Repo جديد (GitHubSyncer) | ⬜ |
| 3 | Auto-Upgrade Feature | ⬜ |
| 4 | Database Auto-Detection | ⬜ |
| 5 | GitHubSyncer Volume Integration | ⬜ |
| 6 | Custom Addons (extra-addons) | ⬜ |
| 7 | Database Initialization | ⬜ |
| 8 | Package Installation | ⬜ |
| 9 | Healthcheck | ⬜ |
| 10 | User Permissions | ⬜ |

---

## Troubleshooting

### المشكلة: Containers لا تعمل

```bash
docker compose down
docker compose up -d
docker compose logs
```

### المشكلة: GitHubSyncer volume غير موجود

```bash
# تحقق من الـ volumes
docker volume ls | grep githubsyncer

# إذا غير موجود، شغّل GitHubSyncer أولاً
cd /path/to/GitHubSyncer
docker compose up -d
```

### المشكلة: Auto-upgrade لا يعمل

```bash
# تحقق من الـ logs
docker compose logs odoo | grep -i upgrade

# تحقق من DATABASE
docker compose exec db psql -U odoo -d postgres -c "\l"
```

### المشكلة: Modules لا تظهر

```bash
# تحقق من addons_path
docker compose exec odoo cat /etc/odoo/erp.conf | grep addons_path

# Update apps list في Odoo UI
```

---

## Script للاختبار السريع

انظر `test-all.sh` للاختبار الآلي لجميع المزايا!
