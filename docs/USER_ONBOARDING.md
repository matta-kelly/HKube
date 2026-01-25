# User Onboarding Guide

## Overview

This guide covers onboarding new users who need access to Landl services (DuckLake, Airbyte, etc).

---

## Pre-requisites (One-Time Setup - Already Done)

- ✅ Headscale OIDC enabled and connected to Authentik
- ✅ Authentik OAuth provider created for Headscale
- ✅ `landl-users` group exists in Authentik
- ✅ Headscale ACL configured with landl-users rules
- ✅ Infrastructure nodes tagged as `tag:infra`

---

## Part 1: Admin Tasks (You Do This)

### Step 1: Create User in Authentik

1. Login to Authentik admin: `https://auth.kube.datamountainsolutions.com`
2. Navigate: **Directory → Users → Create**
3. Fill in details:
   - **Username:** `matthew.kelly@lotusandluna.com` (their email)
   - **Display Name:** `Matt's Landl User - Test Account` (or their real name)
   - **User type:** **External** (prevents admin access to Authentik itself)
   - **Email Address:** Same as username
   - **Path:** `users` (default)
   - **Active:** ✅ Enabled
4. Set temporary password or send password reset link
5. Click **Create**

### Step 2: Add User to landl-users Group

1. In Authentik: **Directory → Groups → landl-users**
2. Click **Users** tab
3. Click **Add existing user**
4. Select the user you just created
5. Click **Add**

### Step 3: Add User Email to Headscale ACL

SSH to anchor VPS and edit the ACL file:

```bash
ssh anchor-vps
sudo nano /etc/headscale/acl.yaml
```

Add the user's email to the `group:landl-users` array:

```json
{
  "groups": {
    "group:admin": ["mkultra@datamountainsolutions.com"],
    "group:landl-users": [
      "matthew.kelly@lotusandluna.com"
      // Add more users here as needed
    ]
  },
  ...
}
```

Save and restart Headscale:

```bash
sudo systemctl restart headscale
```

**Alternative (from your workstation):**

```bash
cd ~/bode/h-kube
# Edit the template
nano ansible/roles/headscale/templates/acl.yaml.j2

# Add user to group:landl-users array, then deploy
make anchor-configure
```

### Step 4: Send Instructions to User

Email template:

```
Subject: Landl Network Access Setup

Hi [Name],

You now have access to Landl services (DuckLake database, Airbyte, etc).

Step 1: Install Tailscale
- Download from: https://tailscale.com/download/windows
- Install with default settings

Step 2: Connect to VPN
- Open Command Prompt or PowerShell
- Run: tailscale up --login-server=https://headscale.datamountainsolutions.com
- Your browser will open automatically
- Login with these credentials:
  - Username: [their email]
  - Password: [temp password or reset link]

Step 3: Access Services
Once connected, you can access:
- DuckLake Database:
  - Host: 100.64.0.4 (or monkeybusiness)
  - Port: 5432
  - Use this in Power BI, DBeaver, etc.
- Web Services:
  - Airbyte: https://airbyte.landl.datamountainsolutions.com
  - (Other services as they're added)

Questions? Reply to this email.
```

---

## Part 2: User Tasks (They Do This)

### Step 1: Install Tailscale

1. Go to https://tailscale.com/download/windows
2. Download Windows installer
3. Run installer (accept defaults)

### Step 2: Join VPN

1. Open **Command Prompt** or **PowerShell**
2. Run:
   ```powershell
   tailscale up --login-server=https://headscale.datamountainsolutions.com
   ```
3. Browser opens automatically
4. Should see Authentik login page at `auth.kube.datamountainsolutions.com`
5. Login with provided credentials
6. Browser shows success message
7. Tailscale icon in system tray shows **Connected**

**Troubleshooting:**
- If already connected to regular Tailscale: Run `tailscale logout` first
- If browser doesn't open: Copy the URL from terminal and paste in browser
- If "unauthorized principal": Check that email domain is in Headscale allowed_domains

### Step 3: Test Access

#### Test 1: DuckLake Database
Using Power BI or any database client:
- **Host:** `100.64.0.4` or `monkeybusiness`
- **Port:** `5432`
- **Database:** `ducklake`
- **Should connect:** ✅

#### Test 2: Web Services
- Open browser
- Visit: `https://airbyte.landl.datamountainsolutions.com`
- Should load and prompt for Authentik login (if not already logged in)
- **Should work:** ✅

#### Test 3: Verify Restrictions (Should Fail)
- Try: `ssh mkultra@100.64.0.1`
- **Should timeout:** ❌ (SSH not allowed for landl-users)

---

## Removing User Access

### Option 1: Temporarily Disable
1. In Authentik: **Directory → Users → [user]**
2. Toggle **Active** to OFF
3. User can no longer login (keeps account for later)

### Option 2: Permanent Removal
1. Remove from Authentik group: **Directory → Groups → landl-users → Remove user**
2. Remove from Headscale ACL:
   ```bash
   ssh anchor-vps
   sudo nano /etc/headscale/acl.yaml
   # Remove email from group:landl-users array
   sudo systemctl restart headscale
   ```
3. (Optional) Delete Authentik user entirely: **Directory → Users → Delete**

---

## Adding Multiple Users

To onboard multiple users at once:

1. Create all Authentik accounts (Step 1 for each)
2. Add all to `landl-users` group at once
3. Update ACL with all emails in one go:
   ```json
   "group:landl-users": [
     "user1@lotusandluna.com",
     "user2@lotusandluna.com",
     "user3@lotusandluna.com"
   ]
   ```
4. Restart Headscale once
5. Send instructions to all users

---

## Common Issues

### "Domain mismatch" error
**Cause:** User's email domain not in Headscale `allowed_domains`
**Fix:** Add domain to `/etc/headscale/config.yaml` under `allowed_domains`, restart Headscale

### "Unauthorized principal" error
**Cause:** User not in Authentik `landl-users` group
**Fix:** Add user to group in Authentik

### User can login but has no network access
**Cause:** Email not in Headscale ACL file
**Fix:** Add email to `group:landl-users` in `/etc/headscale/acl.yaml`, restart Headscale

### User can't access DuckLake but web apps work
**Cause:** Not connected to VPN
**Fix:** Run `tailscale up --login-server=...` command

---

## User Access Summary

After onboarding, users will have:

✅ **Access TO:**
- DuckLake Postgres database (port 5432)
- Web services on `*.landl.datamountainsolutions.com` (ports 80/443)
- Both via VPN and directly (web apps are public but SSO-protected)

❌ **NO Access TO:**
- SSH to any nodes
- Other ports on infrastructure nodes
- Kubernetes cluster access
- Authentik admin panel (External user type prevents this)
- Any admin functions

For admin-level access, create a separate `@datamountainsolutions.com` account in the `admin` group instead.
