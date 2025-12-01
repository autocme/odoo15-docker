# Quick Setup Guide: Odoo 15 with GitHubSyncer

## 🎯 **Architecture**

```
odoo-core (Framework)          → Docker Image
    ↓
odoo-core-addons (435 modules) → GitHubSyncer → Shared Volume
    ↓
Odoo Containers                → Mount volume read-only
```

---

## 🚀 **Setup Steps**

### **Step 1: Configure GitHubSyncer**

```bash
# 1. Start GitHubSyncer
docker compose -f docker-compose.githubsyncer.example.yml up -d githubsyncer syncer-db

# 2. Access GitHubSyncer UI
open http://localhost:5000

# 3. Add Repository in UI:
Repository Name: odoo-core-addons
GitHub URL: https://github.com/autocme/odoo-core-addons.git
Local Path: /app/repos/odoo-core-addons
Branch: main

# 4. Initial Pull
Click "Pull Now" to download all addons (~200MB)

# 5. Discover Containers
Click "Discover Containers" (after starting Odoo)

# 6. Link Containers
Link odoo15-basic and odoo15-full to "odoo-core-addons" repo
```

---

### **Step 2: Start Odoo**

```bash
# After GitHubSyncer pulls the addons, start Odoo
docker compose -f docker-compose.githubsyncer.example.yml up -d db odoo-basic

# Watch logs
docker compose -f docker-compose.githubsyncer.example.yml logs -f odoo-basic
```

---

### **Step 3: Verify Addons**

```bash
# Check addons are present in container
docker exec odoo15-basic ls /opt/odoo/addons | wc -l
# Should show: 435

# List some modules
docker exec odoo15-basic ls /opt/odoo/addons
# Should show: account, sale, purchase, crm, website, pos, hr, l10n_*, etc.
```

### **Step 4: Create Database from Odoo UI**

```bash
# 1. Access Odoo
open http://localhost:8069

# 2. You'll see "Create Database" screen
# Fill in:
#   - Master Password: admin_secure_password_change_me (from docker-compose.yml)
#   - Database Name: my_company_db
#   - Email: admin@example.com
#   - Password: (your admin password)
#   - Language: English (or your preference)
#   - Country: (your country)
#   - Demo Data: uncheck for production

# 3. Click "Create Database"
# Wait 1-2 minutes for initialization

# 4. You'll be logged in with all 435 modules available!
```

---

## 🔄 **Workflow: Updating Addons**

```bash
# Developer updates addon in GitHub
git commit -m "Update sale module"
git push origin main

# GitHub sends webhook to GitHubSyncer
# ↓
# GitHubSyncer pulls latest changes
# ↓
# GitHubSyncer restarts Odoo containers
# ↓
# Odoo loads updated addons automatically
```

---

## 📁 **Volume Structure**

```
odoo-addons-shared (Docker volume)
    ↓ mounted as /app/repos in GitHubSyncer
    └── odoo-core-addons/
        ├── account/
        ├── sale/
        ├── purchase/
        ├── crm/
        ├── website/
        ├── pos/
        ├── hr/
        ├── l10n_us/
        ├── l10n_fr/
        └── ... (435 total modules)

    ↓ mounted as /opt/odoo/addons in Odoo containers (read-only)
```

---

## ⚙️ **Configuration**

### **addons_path Order**

```yaml
conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons,/mnt/extra-addons"
                   ↑ Framework         ↑ odoo-core-addons  ↑ Custom
```

1. `/opt/odoo/odoo/addons` - Framework addons (in image)
2. `/opt/odoo/addons` - odoo-core-addons (from GitHubSyncer)
3. `/mnt/extra-addons` - Your custom modules (optional)

---

## 🔍 **Troubleshooting**

### **Problem: Addons not found**

```bash
# Check if GitHubSyncer pulled the repo
docker exec odoo-addons-syncer ls -la /app/repos/odoo-core-addons

# Check if volume is mounted in Odoo
docker exec odoo15-basic ls -la /opt/odoo/addons
```

### **Problem: Container not restarting after update**

```bash
# Check container label
docker inspect odoo15-basic | grep restart-after

# Should show: "restart-after: odoo-core-addons"

# Check GitHubSyncer logs
docker logs odoo-addons-syncer
```

### **Problem: Database init fails**

```bash
# Make sure addons are pulled BEFORE initializing database
# 1. Start GitHubSyncer first
# 2. Pull addons
# 3. Then start Odoo
```

---

## 📝 **Notes**

1. **First-time setup**: GitHubSyncer must pull addons BEFORE starting Odoo
2. **Read-only mounts**: Prevents containers from modifying shared addons
3. **Separate data**: Each container has its own database and filestore
4. **GitHubSyncer access**: Public repos work without credentials; private repos need SSH key or token

---

## 🎯 **Production Checklist**

- [ ] Change `conf.admin_passwd` in docker-compose.yml
- [ ] Change database passwords (PostgreSQL)
- [ ] Configure GitHub webhook for auto-updates
- [ ] Set up reverse proxy with SSL (nginx/traefik)
- [ ] Configure backup strategy for databases
- [ ] Set resource limits (CPU/memory) on containers
- [ ] Monitor GitHubSyncer logs for sync failures

---

**Ready to test!** 🚀
