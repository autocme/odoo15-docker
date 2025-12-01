# Odoo 15 Docker - Logging Architecture

## نظرة عامة على ملفات الـ Logs

المشروع يستخدم **نظام logging مزدوج** للمرونة والتوافق مع Docker best practices.

---

## 📊 جدول ملفات الـ Logs

| # | نوع الـ Log | المسار/الوصول | التخزين | الاستخدام الرئيسي | اللوق الرئيسي؟ |
|---|------------|--------------|---------|-------------------|----------------|
| **1** | **Container Logs (stdout/stderr)** | `docker compose logs odoo` | Docker logging driver | **Entrypoint logs + Odoo startup** | ✅ **نعم** |
| **2** | **Odoo Application Log** | `/var/lib/odoo/logs/odoo.log` | Volume: `odoo-data` | Odoo runtime logs (requests, errors) | ✅ **نعم** |
| **3** | **Database Logs** | `docker compose logs db` | Docker logging driver | PostgreSQL logs | ❌ ثانوي |
| **4** | **Entrypoint Logs** | Part of Container Logs | Docker stdout | Setup & initialization | ✅ مهم |

---

## 1️⃣ Container Logs (stdout/stderr) - اللوق الأساسي للـ Container

### 📍 الوصول:
```bash
# Real-time monitoring
docker compose logs -f odoo

# آخر 100 سطر
docker compose logs --tail=100 odoo

# مع timestamps
docker compose logs -t odoo

# حفظ في ملف
docker compose logs odoo > odoo-container-logs.txt
```

### 📝 المحتوى:
```
[INFO] 2025-11-30 05:06:05 - ==========================================
[INFO] 2025-11-30 05:06:05 - Odoo 15 Production Container Starting...
[INFO] 2025-11-30 05:06:05 - ==========================================
[INFO] 2025-11-30 05:06:05 - Setting up user permissions (PUID=1000, PGID=1000)...
[INFO] 2025-11-30 05:06:06 - User 'odoo' configured with UID 1000 and GID 1000
[INFO] 2025-11-30 05:06:06 - Generating Odoo configuration at /etc/odoo/erp.conf...
[INFO] 2025-11-30 05:06:07 -   Config: db_host = db
[INFO] 2025-11-30 05:06:07 -   Config: addons_path = /opt/odoo/odoo/addons,/mnt/synced-addons/odoo-core-addons,/mnt/extra-addons
[INFO] 2025-11-30 05:06:07 - Configuration file generated successfully.
[INFO] 2025-11-30 05:06:07 - Installing Python packages: phonenumbers,python-stdnum,num2words...
[INFO] 2025-11-30 05:06:08 - Python packages installed successfully.
[INFO] 2025-11-30 05:06:08 - Installing NPM packages: rtlcss,less...
[INFO] 2025-11-30 05:06:11 - NPM packages installed successfully.
[INFO] 2025-11-30 05:06:11 - INITDB_OPTIONS not set, skipping database initialization.
[INFO] 2025-11-30 05:06:11 - ODOO_DB_NAME not set, auto-detecting Odoo database...
[INFO] 2025-11-30 05:06:11 - Auto-detected database: production
[INFO] 2025-11-30 05:06:11 - Running click-odoo-update for database: production...
[INFO] 2025-11-30 05:06:15 - Automatic upgrade completed successfully.
[INFO] 2025-11-30 05:06:15 - Starting Odoo...
```

### ✅ **متى تستخدمه:**
- ✅ **Troubleshooting startup issues**
- ✅ تتبع entrypoint execution
- ✅ مراقبة database initialization
- ✅ التحقق من auto-upgrade
- ✅ Container health monitoring

### 📌 **الأهمية:** ⭐⭐⭐⭐⭐ (أساسي)

---

## 2️⃣ Odoo Application Log - اللوق الرئيسي للتطبيق

### 📍 المسار:
```
/var/lib/odoo/logs/odoo.log
```

### 📦 التخزين:
```yaml
# في docker-compose.yml
volumes:
  - odoo-data:/var/lib/odoo  # يحتوي على logs/odoo.log
```

### 🔧 الإعداد:
```yaml
# في docker-compose.yml
environment:
  conf.logfile: /var/lib/odoo/logs/odoo.log
  conf.log_level: info
  conf.log_handler: :INFO
```

### 📍 الوصول:
```bash
# قراءة الملف بالكامل
docker compose exec odoo cat /var/lib/odoo/logs/odoo.log

# Real-time monitoring
docker compose exec odoo tail -f /var/lib/odoo/logs/odoo.log

# آخر 50 سطر
docker compose exec odoo tail -50 /var/lib/odoo/logs/odoo.log

# البحث عن أخطاء
docker compose exec odoo grep -i error /var/lib/odoo/logs/odoo.log

# البحث مع سياق (5 أسطر قبل/بعد)
docker compose exec odoo grep -i -C 5 error /var/lib/odoo/logs/odoo.log
```

### 📝 المحتوى:
```
2025-11-30 05:06:20,123 1 INFO production odoo.modules.loading: Modules loaded.
2025-11-30 05:06:20,456 1 INFO production werkzeug: 172.18.0.1 - - [30/Nov/2025 05:06:20] "GET /web HTTP/1.1" 200 -
2025-11-30 05:06:21,789 1 INFO production odoo.http: HTTP Configuring static files
2025-11-30 05:06:22,012 1 INFO production odoo.service.server: HTTP service (werkzeug) running on 0.0.0.0:8069
2025-11-30 05:07:15,234 1 INFO production odoo.addons.base.models.res_users: Login successful for user 'admin' from 172.18.0.1
2025-11-30 05:07:30,567 1 INFO production odoo.models: sale.order: create([{'name': 'SO001', ...}])
2025-11-30 05:08:45,890 1 WARNING production odoo.models: Field 'x_custom_field' does not exist
2025-11-30 05:09:12,345 1 ERROR production odoo.http: Exception during request handling
Traceback (most recent call last):
  ...
```

### ✅ **متى تستخدمه:**
- ✅ **تتبع HTTP requests**
- ✅ **مراقبة database queries**
- ✅ **تشخيص runtime errors**
- ✅ تتبع user actions (login, CRUD operations)
- ✅ Performance monitoring
- ✅ Module-specific logs

### 📌 **الأهمية:** ⭐⭐⭐⭐⭐ (أساسي)

---

## 3️⃣ Database Logs (PostgreSQL)

### 📍 الوصول:
```bash
# Container logs
docker compose logs -f db

# آخر 100 سطر
docker compose logs --tail=100 db
```

### 📝 المحتوى:
```
2025-11-30 02:06:05 UTC [1] LOG:  starting PostgreSQL 14.10 on x86_64-pc-linux-musl
2025-11-30 02:06:05 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2025-11-30 02:06:05 UTC [1] LOG:  database system was shut down at 2025-11-30 02:00:00 UTC
2025-11-30 02:06:05 UTC [1] LOG:  database system is ready to accept connections
2025-11-30 02:06:20 UTC [45] ERROR:  relation "ir_module_module" does not exist at character 15
```

### ✅ **متى تستخدمه:**
- ✅ Database connection issues
- ✅ SQL errors
- ✅ Performance tuning
- ❌ ليس للاستخدام اليومي

### 📌 **الأهمية:** ⭐⭐⭐ (ثانوي)

---

## 4️⃣ Entrypoint Logs

### 📍 جزء من Container Logs

الـ entrypoint script يكتب logs إلى stdout/stderr باستخدام:

```bash
# في entrypoint.sh
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}
```

### 📝 أمثلة:
```
[INFO] 2025-11-30 05:06:05 - Setting up user permissions (PUID=1000, PGID=1000)...
[WARN] 2025-11-30 05:06:11 - click-odoo-update exited with code 1. Continuing startup...
[ERROR] 2025-11-30 05:06:15 - Failed to connect to database
```

### ✅ **متى تستخدمه:**
- ✅ **Startup troubleshooting**
- ✅ Configuration validation
- ✅ Auto-upgrade status
- ✅ Permission issues

### 📌 **الأهمية:** ⭐⭐⭐⭐⭐ (أساسي للـ debugging)

---

## 🎯 أي لوق هو الرئيسي؟

### الإجابة: **يعتمد على السيناريو!**

| السيناريو | اللوق الرئيسي | السبب |
|-----------|---------------|--------|
| **Container لا يبدأ** | Container Logs (stdout) | يحتوي على entrypoint logs |
| **Auto-upgrade issues** | Container Logs | يحتوي على click-odoo-update output |
| **Database init problems** | Container Logs | يحتوي على click-odoo-initdb output |
| **Odoo runtime errors** | Application Log (/var/lib/odoo/logs/odoo.log) | يحتوي على traceback مفصّل |
| **HTTP 500 errors** | Application Log | يحتوي على request details |
| **Module installation** | Application Log | يحتوي على module loading logs |
| **SQL errors** | Database Logs | يحتوي على PostgreSQL errors |
| **Permission errors** | Container Logs | يحتوي على entrypoint permission setup |

---

## 📋 **Best Practices للـ Logging**

### 1️⃣ **للتطوير (Development):**

```yaml
# استخدم كلا النظامين
conf.logfile: /var/lib/odoo/logs/odoo.log
conf.log_level: debug
conf.log_handler: :DEBUG

# راقب كليهما
docker compose logs -f odoo &
docker compose exec odoo tail -f /var/lib/odoo/logs/odoo.log
```

### 2️⃣ **للإنتاج (Production):**

**Option A: File-based (موصى به)**
```yaml
conf.logfile: /var/lib/odoo/logs/odoo.log
conf.log_level: info
conf.log_handler: :INFO
```

**Option B: Stdout-based (للـ container orchestration)**
```yaml
conf.logfile: False  # يكتب إلى stdout
conf.log_level: info
```

### 3️⃣ **Log Rotation:**

إذا كنت تستخدم file-based logging، أضف log rotation:

```bash
# إنشاء /etc/logrotate.d/odoo
/var/lib/odoo/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 odoo odoo
    sharedscripts
}
```

---

## 🔍 **سيناريوهات Troubleshooting الشائعة**

### المشكلة 1: Container يتوقف فوراً

**اللوق المطلوب:** Container Logs
```bash
docker compose logs odoo | grep -i error
```

### المشكلة 2: Internal Server Error (500)

**اللوق المطلوب:** Application Log
```bash
docker compose exec odoo tail -100 /var/lib/odoo/logs/odoo.log | grep -i error
```

### المشكلة 3: Database connection failed

**الأولوية:**
1. Container Logs (entrypoint database setup)
2. Database Logs (PostgreSQL)
```bash
docker compose logs db | grep -i error
docker compose logs odoo | grep -i database
```

### المشكلة 4: Auto-upgrade لا يعمل

**اللوق المطلوب:** Container Logs
```bash
docker compose logs odoo | grep -i upgrade
```

### المشكلة 5: Module لا يُثبّت

**اللوق المطلوب:** Application Log
```bash
docker compose exec odoo grep "module_name" /var/lib/odoo/logs/odoo.log
```

---

## 📊 **ملخص سريع**

```
┌─────────────────────────────────────────────────────────────┐
│  ملفات الـ Logs في المشروع                                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1️⃣ Container Logs (stdout/stderr)                          │
│     📍 docker compose logs odoo                             │
│     ✅ Entrypoint + Startup + Auto-upgrade                  │
│     ⭐ اللوق الرئيسي للـ initialization                      │
│                                                             │
│  2️⃣ Application Log (/var/lib/odoo/logs/odoo.log)           │
│     📍 docker compose exec odoo cat /var/lib/odoo/logs/odoo.log │
│     ✅ Runtime + HTTP + Errors + Performance                │
│     ⭐ اللوق الرئيسي للـ runtime issues                      │
│                                                             │
│  3️⃣ Database Logs                                           │
│     📍 docker compose logs db                               │
│     ✅ PostgreSQL errors + connections                      │
│     ⭐ ثانوي                                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 الخلاصة

### **عدد ملفات الـ Logs:** 2 رئيسية + 1 ثانوية

1. ✅ **Container Logs** - للـ startup & initialization
2. ✅ **Application Log** - للـ runtime & errors
3. ⚠️ Database Logs - ثانوي

### **اللوق الرئيسي:**

**لا يوجد "لوق رئيسي واحد"** - نحن نستخدم **dual logging** للمرونة:

- **Startup/Init issues** → Container Logs ⭐
- **Runtime/HTTP issues** → Application Log ⭐

**Best Practice:** راقب **كليهما** في نفس الوقت:
```bash
# Terminal 1
docker compose logs -f odoo

# Terminal 2
docker compose exec odoo tail -f /var/lib/odoo/logs/odoo.log
```

هذا يعطيك **رؤية شاملة** لكل ما يحدث! 🚀
