# Odoo Addons Structure with GitHubSyncer

## 📁 Recommended Directory Structure

When GitHubSyncer pulls your addons repository, organize it like this:

```
/app/repos/odoo-addons/  (GitHubSyncer managed volume)
├── core/                # Odoo official addons
│   ├── sale/
│   ├── purchase/
│   ├── account/
│   ├── stock/
│   ├── crm/
│   └── ...
│
├── enterprise/          # Odoo Enterprise addons (if you have license)
│   ├── web_studio/
│   ├── helpdesk/
│   └── ...
│
├── custom/              # Your custom developed addons
│   ├── my_company_module/
│   │   ├── __init__.py
│   │   ├── __manifest__.py
│   │   ├── models/
│   │   ├── views/
│   │   └── security/
│   └── another_custom_module/
│
├── third-party/         # Community/third-party addons
│   ├── web_responsive/
│   ├── pos_restaurant_extended/
│   └── ...
│
└── clients/             # Client-specific addons (multi-tenant)
    ├── client1/
    │   └── client1_customization/
    └── client2/
        └── client2_customization/
```

---

## 🎯 Configuring `addons_path` per Container

Each Odoo container can choose which addon directories to use via `conf.addons_path`:

### **Scenario 1: Basic Container (Core only)**

```yaml
odoo-basic:
  environment:
    conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons/core"
```

**Loaded addons:** Framework + Core official addons

---

### **Scenario 2: Custom Development Container**

```yaml
odoo-dev:
  environment:
    conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons/core,/opt/odoo/addons/custom"
```

**Loaded addons:** Framework + Core + Your custom modules

---

### **Scenario 3: Full Production Container**

```yaml
odoo-production:
  environment:
    conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons/core,/opt/odoo/addons/enterprise,/opt/odoo/addons/custom,/opt/odoo/addons/third-party"
```

**Loaded addons:** Everything!

---

### **Scenario 4: Client-Specific Container (Multi-tenant)**

```yaml
odoo-client1:
  environment:
    conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons/core,/opt/odoo/addons/clients/client1"
```

**Loaded addons:** Framework + Core + Client1 specific modules

---

## 🔄 GitHubSyncer Repository Setup

### **Option A: Single Repository (Recommended)**

Create ONE GitHub repository containing all addon categories:

```
Repository: autocme/odoo-addons
├── core/
├── custom/
└── third-party/
```

**GitHubSyncer Configuration:**
- Repository Name: `odoo-addons-repo`
- Clone Path: `/app/repos/odoo-addons`
- Linked Containers: All Odoo containers with label `restart-after: odoo-addons-repo`

---

### **Option B: Multiple Repositories**

Create separate repositories for each category:

```
Repository 1: autocme/odoo-core-addons       → /app/repos/core
Repository 2: autocme/odoo-custom-addons     → /app/repos/custom
Repository 3: autocme/odoo-third-party       → /app/repos/third-party
```

**Then use symlinks or separate volume mounts.**

---

## 🚀 Workflow

### **1. Initial Setup**

```bash
# Clone your addons repo locally
git clone git@github.com:autocme/odoo-addons.git

# Organize addons
cd odoo-addons
mkdir -p core custom third-party

# Copy Odoo official addons
cp -r /path/to/odoo/addons/* core/

# Add your custom modules
cp -r /path/to/my_modules/* custom/

# Commit and push
git add .
git commit -m "Initial addons structure"
git push origin main
```

### **2. Configure GitHubSyncer**

1. Access GitHubSyncer UI: `http://localhost:5000`
2. Add Repository:
   - Name: `odoo-addons-repo`
   - GitHub URL: `git@github.com:autocme/odoo-addons.git`
   - Local Path: `/app/repos/odoo-addons`
   - Branch: `main`
3. Add SSH Key or GitHub Token
4. Click "Discover Containers"
5. Link containers with label `restart-after: odoo-addons-repo`

### **3. Development Workflow**

```bash
# Make changes locally
cd odoo-addons/custom/my_module
# ... edit files ...

# Commit and push
git add .
git commit -m "Update my_module: add new feature"
git push origin main
```

**What happens next:**
1. GitHub sends webhook to GitHubSyncer
2. GitHubSyncer pulls latest changes to `/app/repos/odoo-addons`
3. GitHubSyncer restarts linked Odoo containers
4. Odoo reloads with updated addons

---

## ⚠️ Important Notes

### **1. Read-Only Mounts**

Always mount the shared addons volume as **read-only** (`:ro`):

```yaml
volumes:
  - odoo-addons-shared:/opt/odoo/addons:ro
```

**Why?** Prevents containers from modifying shared addons.

### **2. Framework Addons**

The path `/opt/odoo/odoo/addons` contains Odoo framework addons (web, mail, etc.) and must ALWAYS be first in `addons_path`:

```yaml
conf.addons_path: "/opt/odoo/odoo/addons,..."  # ← Always first!
```

### **3. Addon Dependencies**

If a custom addon depends on a third-party addon, ensure both directories are in `addons_path`:

```yaml
conf.addons_path: "/opt/odoo/odoo/addons,/opt/odoo/addons/core,/opt/odoo/addons/third-party,/opt/odoo/addons/custom"
```

### **4. Database vs Filesystem**

- **Addons on filesystem:** Managed by GitHubSyncer in `/opt/odoo/addons`
- **Installed addons:** Tracked in database (separate per container)

Each container can have different **installed** modules from the same shared addons.

---

## 🔍 Troubleshooting

### **Addon not found**

```bash
# Check if addon exists in volume
docker exec odoo15-basic ls -la /opt/odoo/addons/custom/my_module

# Check addons_path configuration
docker exec odoo15-basic cat /etc/odoo/erp.conf | grep addons_path
```

### **Container not restarting after update**

```bash
# Check container labels
docker inspect odoo15-basic | grep restart-after

# Check GitHubSyncer logs
docker logs odoo-addons-syncer

# Manually restart
docker restart odoo15-basic
```

### **Permission issues**

```bash
# Ensure correct ownership in volume
docker exec odoo-addons-syncer chown -R 1000:1000 /app/repos/odoo-addons
```

---

## 📚 Best Practices

1. ✅ **Keep addons organized** in subdirectories (core, custom, third-party)
2. ✅ **Use read-only mounts** for shared addons
3. ✅ **Separate data volumes** per container
4. ✅ **Test in dev** before pushing to production
5. ✅ **Use semantic versioning** for custom addons
6. ✅ **Document dependencies** in addon manifests
7. ✅ **Backup databases** before major updates

---

## 🎓 Example: Adding a New Custom Addon

```bash
# 1. Create addon locally
cd odoo-addons/custom
mkdir my_new_addon
cd my_new_addon

# 2. Create addon structure
cat > __manifest__.py <<EOF
{
    'name': 'My New Addon',
    'version': '15.0.1.0.0',
    'depends': ['base', 'sale'],
    'data': [
        'views/views.xml',
    ],
}
EOF

# 3. Commit and push
git add .
git commit -m "Add my_new_addon"
git push origin main

# 4. GitHubSyncer automatically:
#    - Pulls the changes
#    - Restarts Odoo containers

# 5. Install in Odoo UI:
#    - Apps menu → Update Apps List
#    - Search "My New Addon"
#    - Install
```

---

**Happy Odoo Development! 🚀**
