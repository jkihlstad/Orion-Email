import { Hono } from "hono";
import type { Env } from "../env";
import { convexFetch } from "../convexClient";

export const googleOAuthRoute = new Hono<{ Bindings: Env }>();

const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3";

// Scopes for calendar access
const SCOPES = [
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events",
  "https://www.googleapis.com/auth/userinfo.email",
].join(" ");

// Generate PKCE code verifier and challenge
function generateCodeVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function generateCodeChallenge(verifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

// Start OAuth flow - returns URL to redirect user to
googleOAuthRoute.get("/oauth/google/start", async (c) => {
  const clerkUserId = c.req.query("user");
  if (!clerkUserId) {
    return c.json({ error: "Missing user parameter" }, 400);
  }

  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);
  const state = crypto.randomUUID();

  // Store verifier and user in KV (expires in 10 minutes)
  await c.env.OAUTH_TOKENS.put(
    `oauth_state:${state}`,
    JSON.stringify({ clerkUserId, codeVerifier }),
    { expirationTtl: 600 }
  );

  const params = new URLSearchParams({
    client_id: c.env.GOOGLE_CLIENT_ID,
    redirect_uri: c.env.GOOGLE_REDIRECT_URI,
    response_type: "code",
    scope: SCOPES,
    state,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
    access_type: "offline",
    prompt: "consent",
  });

  const authUrl = `${GOOGLE_AUTH_URL}?${params.toString()}`;

  return c.json({ authUrl, state });
});

// OAuth callback - exchange code for tokens
googleOAuthRoute.get("/oauth/google/callback", async (c) => {
  const code = c.req.query("code");
  const state = c.req.query("state");
  const error = c.req.query("error");

  if (error) {
    return c.html(`
      <html><body style="font-family: -apple-system, sans-serif; padding: 20px;">
        <h2>Authorization Failed</h2>
        <p>Error: ${error}</p>
        <p>You can close this window.</p>
      </body></html>
    `);
  }

  if (!code || !state) {
    return c.html(`
      <html><body style="font-family: -apple-system, sans-serif; padding: 20px;">
        <h2>Invalid Request</h2>
        <p>Missing authorization code or state.</p>
      </body></html>
    `);
  }

  // Retrieve stored state
  const storedData = await c.env.OAUTH_TOKENS.get(`oauth_state:${state}`);
  if (!storedData) {
    return c.html(`
      <html><body style="font-family: -apple-system, sans-serif; padding: 20px;">
        <h2>Session Expired</h2>
        <p>Please try connecting again.</p>
      </body></html>
    `);
  }

  const { clerkUserId, codeVerifier } = JSON.parse(storedData);
  await c.env.OAUTH_TOKENS.delete(`oauth_state:${state}`);

  // Exchange code for tokens
  const tokenResponse = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: c.env.GOOGLE_CLIENT_ID,
      client_secret: c.env.GOOGLE_CLIENT_SECRET,
      code,
      code_verifier: codeVerifier,
      grant_type: "authorization_code",
      redirect_uri: c.env.GOOGLE_REDIRECT_URI,
    }),
  });

  if (!tokenResponse.ok) {
    const errText = await tokenResponse.text();
    console.error("Token exchange failed:", errText);
    return c.html(`
      <html><body style="font-family: -apple-system, sans-serif; padding: 20px;">
        <h2>Authorization Failed</h2>
        <p>Could not complete sign-in. Please try again.</p>
      </body></html>
    `);
  }

  const tokens = await tokenResponse.json() as {
    access_token: string;
    refresh_token?: string;
    expires_in: number;
    scope: string;
  };

  // Get user email
  const userInfoResponse = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  const userInfo = await userInfoResponse.json() as { email: string };

  // Store tokens securely in KV
  const tokenKey = `google_tokens:${clerkUserId}`;
  await c.env.OAUTH_TOKENS.put(
    tokenKey,
    JSON.stringify({
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      expiresAt: Date.now() + tokens.expires_in * 1000,
      email: userInfo.email,
    }),
    { expirationTtl: 365 * 24 * 60 * 60 } // 1 year
  );

  // Notify Convex about account connection
  await convexFetch(c.env, "/calendar/accounts/connect", {
    method: "POST",
    headers: { Authorization: `Bearer dev:${clerkUserId}:user` },
    body: JSON.stringify({
      provider: "google",
      primaryEmail: userInfo.email,
      accessLevel: "full",
      scopes: tokens.scope.split(" "),
    }),
  });

  return c.html(`
    <html><body style="font-family: -apple-system, sans-serif; padding: 20px; text-align: center;">
      <h2>Google Calendar Connected</h2>
      <p>Connected as ${userInfo.email}</p>
      <p>You can close this window and return to the app.</p>
      <script>
        if (window.opener) {
          window.opener.postMessage({ type: 'google-calendar-connected', email: '${userInfo.email}' }, '*');
        }
      </script>
    </body></html>
  `);
});

// Refresh access token
async function refreshAccessToken(env: Env, clerkUserId: string): Promise<string | null> {
  const tokenKey = `google_tokens:${clerkUserId}`;
  const stored = await env.OAUTH_TOKENS.get(tokenKey);
  if (!stored) return null;

  const tokens = JSON.parse(stored);

  // Check if still valid
  if (tokens.expiresAt > Date.now() + 60000) {
    return tokens.accessToken;
  }

  // Refresh token
  if (!tokens.refreshToken) return null;

  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      refresh_token: tokens.refreshToken,
      grant_type: "refresh_token",
    }),
  });

  if (!response.ok) return null;

  const newTokens = await response.json() as { access_token: string; expires_in: number };

  await env.OAUTH_TOKENS.put(
    tokenKey,
    JSON.stringify({
      ...tokens,
      accessToken: newTokens.access_token,
      expiresAt: Date.now() + newTokens.expires_in * 1000,
    }),
    { expirationTtl: 365 * 24 * 60 * 60 }
  );

  return newTokens.access_token;
}

export { refreshAccessToken };
