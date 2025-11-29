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

### **Step 3: Verify**

```bash
# 1. Check addons are present
docker exec odoo15-basic ls -la /opt/odoo/addons

# Should show 435 directories:
# account, sale, purchase, crm, website, pos, hr, l10n_*, etc.

# 2. Access Odoo
open http://localhost:8069

# 3. Create database
# Use Odoo UI to create database with modules you need
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
