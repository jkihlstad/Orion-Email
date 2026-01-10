export type Env = {
  CONVEX_HTTP_BASE: string;
  BRAIN_APPROVAL_TOKEN_SECRET: string;

  // Google OAuth
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  GOOGLE_REDIRECT_URI: string;

  // KV for token storage
  OAUTH_TOKENS: KVNamespace;
};
