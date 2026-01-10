# Orion App - API Keys Setup Guide

Complete setup instructions for all required API keys and services.

---

## Table of Contents

1. [Clerk Authentication](#1-clerk-authentication)
2. [Convex Backend](#2-convex-backend)
3. [Google APIs (Gmail + Calendar)](#3-google-apis-gmail--calendar)
4. [Microsoft/Outlook APIs](#4-microsoftoutlook-apis)
5. [OpenAI APIs](#5-openai-apis)
6. [Final Configuration](#6-final-configuration)

---

## 1. Clerk Authentication

Clerk provides authentication for your app with support for multiple sign-in methods.

### Step 1: Create a Clerk Account

1. Go to [https://clerk.com](https://clerk.com)
2. Click **"Start building for free"**
3. Sign up with GitHub, Google, or email

### Step 2: Create a New Application

1. In the Clerk Dashboard, click **"Add application"**
2. Enter application name: `Orion Email App`
3. Select sign-in options:
   - Email address (recommended)
   - Google OAuth (optional)
   - Apple (recommended for iOS)
4. Click **"Create application"**

### Step 3: Get Your API Keys

1. In your application dashboard, go to **"API Keys"** in the left sidebar
2. Copy these values:

```
CLERK_PUBLISHABLE_KEY=pk_test_xxxxx  (from "Publishable key")
CLERK_SECRET_KEY=sk_test_xxxxx       (from "Secret keys" - click to reveal)
```

### Step 4: Get Issuer URL and JWKS URL

1. Go to **"JWT Templates"** in the left sidebar
2. Your issuer URL is shown at the top, or construct it from your instance:

```
CLERK_ISSUER_URL=https://<your-instance>.clerk.accounts.dev
CLERK_JWKS_URL=https://<your-instance>.clerk.accounts.dev/.well-known/jwks.json
```

**Example:** If your Clerk instance is `noble-cardinal-42`, then:
```
CLERK_ISSUER_URL=https://noble-cardinal-42.clerk.accounts.dev
CLERK_JWKS_URL=https://noble-cardinal-42.clerk.accounts.dev/.well-known/jwks.json
```

### Step 5: Configure for iOS (Optional)

1. Go to **"Domains"** in the left sidebar
2. Note your Frontend API domain:

```
CLERK_FRONTEND_API=<your-instance>.clerk.accounts.dev
```

### Step 6: Configure OAuth Providers (Optional)

To enable Google/Apple sign-in:

1. Go to **"User & Authentication"** → **"Social Connections"**
2. Enable **Google**:
   - You'll need Google OAuth credentials (see Section 3)
   - Enter your Google Client ID and Secret
3. Enable **Apple** (for iOS):
   - Requires Apple Developer account
   - Follow Clerk's Apple Sign-In setup guide

---

## 2. Convex Backend

Convex is the real-time backend database.

### Step 1: Create a Convex Account

1. Go to [https://convex.dev](https://convex.dev)
2. Click **"Get Started"**
3. Sign up with GitHub or Google

### Step 2: Create a New Project

1. In the Convex Dashboard, click **"Create a project"**
2. Enter project name: `orion-email`
3. Select a team (create one if needed)
4. Click **"Create"**

### Step 3: Get Your Deployment URL

1. In your project dashboard, you'll see your deployment URL:

```
CONVEX_URL=https://<your-deployment>.convex.cloud
VITE_CONVEX_URL=https://<your-deployment>.convex.cloud
```

**Example:**
```
CONVEX_URL=https://happy-penguin-123.convex.cloud
```

### Step 4: Get Deploy Key (for CI/CD)

1. Go to **"Settings"** → **"Deploy Keys"**
2. Click **"Generate Deploy Key"**
3. Copy the key:

```
CONVEX_DEPLOY_KEY=prod:xxxxxxxxxxxxx
```

### Step 5: Link Your Local Project

Run in your terminal:

```bash
cd convex
npx convex dev
```

This will:
- Prompt you to log in
- Link to your project
- Create `.env.local` with deployment info
- Generate types in `_generated/`

---

## 3. Google APIs (Gmail + Calendar)

Google APIs are used for Gmail integration and Google Calendar sync.

### Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click the project dropdown at the top → **"New Project"**
3. Enter project name: `Orion Email App`
4. Click **"Create"**
5. Wait for creation, then select the project

### Step 2: Enable Required APIs

1. Go to **"APIs & Services"** → **"Library"**
2. Search and enable each of these:
   - **Gmail API** - Click → **"Enable"**
   - **Google Calendar API** - Click → **"Enable"**
   - **Google People API** - Click → **"Enable"** (for contacts)

### Step 3: Configure OAuth Consent Screen

1. Go to **"APIs & Services"** → **"OAuth consent screen"**
2. Select **"External"** user type → Click **"Create"**
3. Fill in the form:
   - **App name:** `Orion Email`
   - **User support email:** Your email
   - **Developer contact:** Your email
4. Click **"Save and Continue"**

5. **Add Scopes:**
   - Click **"Add or Remove Scopes"**
   - Add these scopes:
     ```
     https://www.googleapis.com/auth/gmail.readonly
     https://www.googleapis.com/auth/gmail.send
     https://www.googleapis.com/auth/gmail.modify
     https://www.googleapis.com/auth/calendar.readonly
     https://www.googleapis.com/auth/calendar.events
     https://www.googleapis.com/auth/userinfo.email
     https://www.googleapis.com/auth/userinfo.profile
     ```
   - Click **"Update"** → **"Save and Continue"**

6. **Add Test Users** (while in testing mode):
   - Click **"Add Users"**
   - Add your email addresses
   - Click **"Save and Continue"**

### Step 4: Create OAuth Credentials

1. Go to **"APIs & Services"** → **"Credentials"**
2. Click **"Create Credentials"** → **"OAuth client ID"**

**For iOS App:**
3. Select **"iOS"** as application type
4. Enter:
   - **Name:** `Orion iOS`
   - **Bundle ID:** `com.orion.emailapp`
5. Click **"Create"**
6. Note the **Client ID** (you won't need a secret for iOS)

**For Web/Workers (Server-side):**
7. Click **"Create Credentials"** → **"OAuth client ID"** again
8. Select **"Web application"**
9. Enter:
   - **Name:** `Orion Web`
   - **Authorized redirect URIs:**
     ```
     https://brain-calendar.YOUR_SUBDOMAIN.workers.dev/oauth/google/callback
     http://localhost:8787/oauth/google/callback
     ```
10. Click **"Create"**
11. Copy your credentials:

```
GOOGLE_CLIENT_ID=xxxxxxxxxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxxxxxxxxx
```

### Step 5: Set Gmail Scopes

```
GMAIL_SCOPES=https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/gmail.send,https://www.googleapis.com/auth/gmail.modify
```

### Publishing to Production

When ready for production:
1. Go to **"OAuth consent screen"**
2. Click **"Publish App"**
3. Complete Google's verification process (may take weeks for sensitive scopes)

---

## 4. Microsoft/Outlook APIs

Microsoft Graph APIs are used for Outlook email integration.

### Step 1: Create an Azure Account

1. Go to [Azure Portal](https://portal.azure.com)
2. Sign in with your Microsoft account
3. If new, you may need to set up a subscription (free tier available)

### Step 2: Register an Application

1. Go to **"Azure Active Directory"** (or search for "App registrations")
2. Click **"App registrations"** → **"New registration"**
3. Fill in:
   - **Name:** `Orion Email App`
   - **Supported account types:** Select **"Accounts in any organizational directory and personal Microsoft accounts"**
   - **Redirect URI:**
     - Platform: **Web**
     - URI: `https://brain-calendar.YOUR_SUBDOMAIN.workers.dev/oauth/microsoft/callback`
4. Click **"Register"**

### Step 3: Get Application IDs

After registration, you'll see:

```
OUTLOOK_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  (Application/Client ID)
OUTLOOK_TENANT_ID=common                                (Use "common" for multi-tenant)
```

### Step 4: Create Client Secret

1. In your app registration, go to **"Certificates & secrets"**
2. Click **"New client secret"**
3. Enter description: `Orion Production`
4. Select expiration: **24 months** (recommended)
5. Click **"Add"**
6. **IMMEDIATELY copy the Value** (it won't be shown again):

```
OUTLOOK_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 5: Configure API Permissions

1. Go to **"API permissions"** → **"Add a permission"**
2. Select **"Microsoft Graph"**
3. Select **"Delegated permissions"**
4. Add these permissions:
   - `Mail.Read`
   - `Mail.Send`
   - `Mail.ReadWrite`
   - `User.Read`
   - `offline_access` (for refresh tokens)
5. Click **"Add permissions"**

6. **(Optional) Grant Admin Consent:**
   - If you're an admin, click **"Grant admin consent for [Your Org]"**
   - This pre-approves permissions for all users in your org

### Step 6: Set Scopes

```
OUTLOOK_SCOPES=Mail.Read,Mail.Send,Mail.ReadWrite,User.Read,offline_access
```

---

## 5. OpenAI APIs

OpenAI is used for AI features, text-to-speech, and speech-to-text.

### Step 1: Create an OpenAI Account

1. Go to [https://platform.openai.com](https://platform.openai.com)
2. Click **"Sign up"**
3. Complete registration with email or Google

### Step 2: Get Your API Key

1. Go to [API Keys](https://platform.openai.com/api-keys)
2. Click **"Create new secret key"**
3. Name it: `Orion Email App`
4. Click **"Create secret key"**
5. **IMMEDIATELY copy the key** (it won't be shown again):

```
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 3: Set Up Billing (Required)

1. Go to [Billing](https://platform.openai.com/account/billing)
2. Click **"Add payment method"**
3. Add a credit card
4. Set a usage limit (recommended: start with $20/month)

### Step 4: Configure Model Settings

```
# Text-to-Speech Configuration
OPENAI_TTS_VOICE=alloy           # Options: alloy, echo, fable, onyx, nova, shimmer
OPENAI_TTS_MODEL=tts-1           # Options: tts-1 (fast), tts-1-hd (high quality)

# Speech-to-Text Configuration
OPENAI_WHISPER_MODEL=whisper-1   # Currently only whisper-1 available
```

### Available TTS Voices

| Voice | Description |
|-------|-------------|
| `alloy` | Neutral, balanced |
| `echo` | Warm, conversational |
| `fable` | Expressive, British |
| `onyx` | Deep, authoritative |
| `nova` | Friendly, upbeat |
| `shimmer` | Clear, gentle |

---

## 6. Final Configuration

### Create Your .env.local File

Create a file at the project root:

```bash
touch .env.local
```

Add all your credentials:

```bash
# =============================================================================
# CLERK AUTHENTICATION
# =============================================================================
CLERK_PUBLISHABLE_KEY=pk_test_xxxxx
CLERK_SECRET_KEY=sk_test_xxxxx
CLERK_ISSUER_URL=https://your-instance.clerk.accounts.dev
CLERK_JWKS_URL=https://your-instance.clerk.accounts.dev/.well-known/jwks.json
CLERK_FRONTEND_API=your-instance.clerk.accounts.dev

# =============================================================================
# CONVEX
# =============================================================================
CONVEX_URL=https://your-deployment.convex.cloud
VITE_CONVEX_URL=https://your-deployment.convex.cloud
CONVEX_DEPLOY_KEY=prod:xxxxx

# =============================================================================
# GOOGLE APIs
# =============================================================================
GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxx
GMAIL_SCOPES=https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/gmail.send,https://www.googleapis.com/auth/gmail.modify

# =============================================================================
# MICROSOFT/OUTLOOK APIs
# =============================================================================
OUTLOOK_CLIENT_ID=xxxxx-xxxxx-xxxxx-xxxxx
OUTLOOK_CLIENT_SECRET=xxxxx
OUTLOOK_TENANT_ID=common
OUTLOOK_SCOPES=Mail.Read,Mail.Send,Mail.ReadWrite,User.Read,offline_access

# =============================================================================
# OPENAI
# =============================================================================
OPENAI_API_KEY=sk-xxxxx
OPENAI_TTS_VOICE=alloy
OPENAI_TTS_MODEL=tts-1
OPENAI_WHISPER_MODEL=whisper-1

# =============================================================================
# BRAIN WORKER (Cloudflare)
# =============================================================================
BRAIN_API_URL=https://brain-calendar.YOUR_SUBDOMAIN.workers.dev
```

### Configure Cloudflare Workers Secrets

For the brain-calendar worker, set secrets:

```bash
cd workers/brain-calendar

# Set secrets (prompted for value)
wrangler secret put GOOGLE_CLIENT_ID
wrangler secret put GOOGLE_CLIENT_SECRET
wrangler secret put CONVEX_HTTP_BASE
wrangler secret put BRAIN_APPROVAL_TOKEN_SECRET
```

### Configure Convex Environment Variables

```bash
cd convex

# Set environment variables in Convex dashboard or via CLI
npx convex env set CLERK_ISSUER_URL "https://your-instance.clerk.accounts.dev"
npx convex env set CLERK_JWKS_URL "https://your-instance.clerk.accounts.dev/.well-known/jwks.json"
```

### iOS App Configuration

Update `EmailApp/Configuration.swift` with your values, or use an `xcconfig` file.

---

## Troubleshooting

### Clerk: "Invalid JWT"
- Verify `CLERK_ISSUER_URL` matches your Clerk instance exactly
- Ensure the JWT hasn't expired
- Check that JWKS URL is accessible

### Google: "Access Denied"
- Ensure your email is in the test users list
- Check that all required scopes are enabled
- Verify OAuth consent screen is configured

### Microsoft: "AADSTS error"
- Check that Client ID and Secret are correct
- Ensure redirect URIs match exactly
- Verify API permissions are granted

### OpenAI: "Rate Limited"
- Check your usage at platform.openai.com
- Verify billing is set up
- Consider implementing retry logic

---

## Security Best Practices

1. **Never commit `.env.local`** - It's in `.gitignore`
2. **Rotate secrets regularly** - Every 90 days minimum
3. **Use minimum scopes** - Only request what you need
4. **Monitor usage** - Set up billing alerts
5. **Use separate keys** - Different keys for dev/staging/prod

---

## Quick Reference: All Environment Variables

| Variable | Service | Required |
|----------|---------|----------|
| `CLERK_PUBLISHABLE_KEY` | Clerk | Yes |
| `CLERK_SECRET_KEY` | Clerk | Yes |
| `CLERK_ISSUER_URL` | Clerk | Yes |
| `CLERK_JWKS_URL` | Clerk | Yes |
| `CONVEX_URL` | Convex | Yes |
| `CONVEX_DEPLOY_KEY` | Convex | For deploy |
| `GOOGLE_CLIENT_ID` | Google | For Google features |
| `GOOGLE_CLIENT_SECRET` | Google | For server-side |
| `OUTLOOK_CLIENT_ID` | Microsoft | For Outlook |
| `OUTLOOK_CLIENT_SECRET` | Microsoft | For Outlook |
| `OUTLOOK_TENANT_ID` | Microsoft | For Outlook |
| `OPENAI_API_KEY` | OpenAI | For AI features |
