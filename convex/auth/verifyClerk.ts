/**
 * Clerk JWT Verification for Convex HTTP Actions
 *
 * This module provides JWT verification for Clerk authentication tokens.
 * It fetches Clerk's JWKS (JSON Web Key Set) to verify token signatures.
 *
 * Environment Variables Required:
 * - CLERK_ISSUER_URL: The Clerk issuer URL (e.g., https://your-app.clerk.accounts.dev)
 *
 * Security Notes:
 * - Tokens are verified using RS256 algorithm
 * - JWKS is cached to avoid repeated fetches
 * - Expired tokens are rejected
 * - Invalid signatures are rejected
 */

import { ActionCtx } from "../_generated/server";

// ============================================================================
// Types
// ============================================================================

interface ClerkJWTPayload {
  /** Subject - the user ID */
  sub: string;
  /** Session ID */
  sid: string;
  /** Issuer */
  iss: string;
  /** Audience */
  aud?: string | string[];
  /** Expiration time (Unix timestamp) */
  exp: number;
  /** Issued at (Unix timestamp) */
  iat: number;
  /** Not before (Unix timestamp) */
  nbf?: number;
  /** JWT ID */
  jti?: string;
  /** Authorized party */
  azp?: string;
}

interface JWK {
  kty: string;
  use?: string;
  key_ops?: string[];
  alg?: string;
  kid: string;
  n?: string;
  e?: string;
  x5c?: string[];
}

interface JWKS {
  keys: JWK[];
}

export interface VerificationResult {
  userId: string;
  sessionId: string;
  exp: number;
}

export class AuthenticationError extends Error {
  constructor(
    message: string,
    public code: string = "UNAUTHORIZED"
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

// ============================================================================
// JWKS Cache
// ============================================================================

/**
 * Simple in-memory cache for JWKS
 * In production, consider using a distributed cache
 */
let jwksCache: { keys: Map<string, CryptoKey>; fetchedAt: number } | null = null;
const JWKS_CACHE_TTL = 3600000; // 1 hour in milliseconds

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Base64URL decode
 */
function base64UrlDecode(input: string): Uint8Array {
  // Replace URL-safe characters and add padding
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Decode JWT without verification (for header inspection)
 */
function decodeJwtHeader(token: string): { alg: string; typ?: string; kid?: string } {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthenticationError("Invalid JWT format", "INVALID_TOKEN");
  }
  const headerJson = new TextDecoder().decode(base64UrlDecode(parts[0]));
  return JSON.parse(headerJson);
}

/**
 * Decode JWT payload without verification
 */
function decodeJwtPayload(token: string): ClerkJWTPayload {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthenticationError("Invalid JWT format", "INVALID_TOKEN");
  }
  const payloadJson = new TextDecoder().decode(base64UrlDecode(parts[1]));
  return JSON.parse(payloadJson);
}

/**
 * Import RSA public key from JWK
 */
async function importRsaPublicKey(jwk: JWK): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      alg: "RS256",
      use: "sig",
    },
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["verify"]
  );
}

/**
 * Fetch JWKS from Clerk
 */
async function fetchJwks(issuerUrl: string): Promise<Map<string, CryptoKey>> {
  // Check cache first
  if (jwksCache && Date.now() - jwksCache.fetchedAt < JWKS_CACHE_TTL) {
    return jwksCache.keys;
  }

  // Construct JWKS URL
  const jwksUrl = `${issuerUrl.replace(/\/$/, "")}/.well-known/jwks.json`;

  const response = await fetch(jwksUrl);
  if (!response.ok) {
    throw new AuthenticationError(
      `Failed to fetch JWKS: ${response.status}`,
      "JWKS_FETCH_FAILED"
    );
  }

  const jwks: JWKS = await response.json();
  const keys = new Map<string, CryptoKey>();

  for (const jwk of jwks.keys) {
    if (jwk.kty === "RSA" && jwk.kid) {
      const cryptoKey = await importRsaPublicKey(jwk);
      keys.set(jwk.kid, cryptoKey);
    }
  }

  // Update cache
  jwksCache = { keys, fetchedAt: Date.now() };

  return keys;
}

/**
 * Verify JWT signature
 */
async function verifyJwtSignature(
  token: string,
  publicKey: CryptoKey
): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return false;
  }

  const [headerB64, payloadB64, signatureB64] = parts;
  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlDecode(signatureB64);

  return crypto.subtle.verify(
    { name: "RSASSA-PKCS1-v1_5" },
    publicKey,
    signature,
    data
  );
}

// ============================================================================
// Main Verification Function
// ============================================================================

/**
 * Verify a Clerk JWT from an Authorization header
 *
 * @param ctx - Convex action context (for accessing environment variables)
 * @param authHeader - The Authorization header value (e.g., "Bearer <token>")
 * @returns VerificationResult with userId, sessionId, and expiration
 * @throws AuthenticationError if verification fails
 *
 * Usage:
 * ```typescript
 * const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));
 * // auth.userId is now available for authorization checks
 * ```
 */
export async function verifyClerkJwt(
  ctx: ActionCtx,
  authHeader: string | null
): Promise<VerificationResult> {
  // Check for Authorization header
  if (!authHeader) {
    throw new AuthenticationError("Missing Authorization header", "MISSING_AUTH");
  }

  // Extract Bearer token
  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    throw new AuthenticationError(
      "Invalid Authorization header format",
      "INVALID_AUTH_FORMAT"
    );
  }

  const token = parts[1];

  // Get issuer URL from environment
  const issuerUrl = process.env.CLERK_ISSUER_URL;
  if (!issuerUrl) {
    throw new AuthenticationError(
      "CLERK_ISSUER_URL not configured",
      "CONFIG_ERROR"
    );
  }

  // Decode header to get key ID
  let header: { alg: string; kid?: string };
  try {
    header = decodeJwtHeader(token);
  } catch {
    throw new AuthenticationError("Invalid JWT header", "INVALID_TOKEN");
  }

  // Verify algorithm
  if (header.alg !== "RS256") {
    throw new AuthenticationError(
      `Unsupported algorithm: ${header.alg}`,
      "INVALID_ALGORITHM"
    );
  }

  // Get the key ID
  const kid = header.kid;
  if (!kid) {
    throw new AuthenticationError("Missing key ID in JWT header", "MISSING_KID");
  }

  // Fetch JWKS and get the signing key
  const keys = await fetchJwks(issuerUrl);
  const publicKey = keys.get(kid);

  if (!publicKey) {
    // Key not found, might be rotated - try refreshing cache
    jwksCache = null;
    const refreshedKeys = await fetchJwks(issuerUrl);
    const refreshedKey = refreshedKeys.get(kid);

    if (!refreshedKey) {
      throw new AuthenticationError(
        "Signing key not found",
        "KEY_NOT_FOUND"
      );
    }
  }

  // Verify signature
  const isValid = await verifyJwtSignature(token, keys.get(kid)!);
  if (!isValid) {
    throw new AuthenticationError("Invalid token signature", "INVALID_SIGNATURE");
  }

  // Decode and validate payload
  let payload: ClerkJWTPayload;
  try {
    payload = decodeJwtPayload(token);
  } catch {
    throw new AuthenticationError("Invalid JWT payload", "INVALID_PAYLOAD");
  }

  // Validate issuer
  if (payload.iss !== issuerUrl) {
    throw new AuthenticationError(
      "Invalid token issuer",
      "INVALID_ISSUER"
    );
  }

  // Validate expiration
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp < now) {
    throw new AuthenticationError("Token has expired", "TOKEN_EXPIRED");
  }

  // Validate not-before (if present)
  if (payload.nbf && payload.nbf > now) {
    throw new AuthenticationError("Token is not yet valid", "TOKEN_NOT_YET_VALID");
  }

  // Return verification result
  return {
    userId: payload.sub,
    sessionId: payload.sid,
    exp: payload.exp,
  };
}

/**
 * Helper to extract user ID from request with proper error handling
 * Returns null instead of throwing if auth fails (for optional auth endpoints)
 */
export async function tryVerifyClerkJwt(
  ctx: ActionCtx,
  authHeader: string | null
): Promise<VerificationResult | null> {
  try {
    return await verifyClerkJwt(ctx, authHeader);
  } catch (error) {
    if (error instanceof AuthenticationError) {
      return null;
    }
    throw error;
  }
}

/**
 * Middleware-style helper that returns an HTTP response on auth failure
 */
export async function requireAuth(
  ctx: ActionCtx,
  request: Request
): Promise<VerificationResult | Response> {
  try {
    const auth = await verifyClerkJwt(ctx, request.headers.get("Authorization"));
    return auth;
  } catch (error) {
    if (error instanceof AuthenticationError) {
      return new Response(
        JSON.stringify({
          error: error.message,
          code: error.code,
        }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        }
      );
    }
    return new Response(
      JSON.stringify({
        error: "Internal authentication error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
}

/**
 * Simplified JWT verification that extracts clerkUserId and role from the request.
 * Throws AuthenticationError if verification fails.
 *
 * @param request - The HTTP request object
 * @returns Object with clerkUserId and role
 * @throws AuthenticationError if verification fails
 */
export async function verifyClerkJwtOrThrow(
  request: Request
): Promise<{ clerkUserId: string; role: string }> {
  const authHeader = request.headers.get("Authorization");

  // Check for Authorization header
  if (!authHeader) {
    throw new AuthenticationError("Missing Authorization header", "MISSING_AUTH");
  }

  // Extract Bearer token
  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    throw new AuthenticationError(
      "Invalid Authorization header format",
      "INVALID_AUTH_FORMAT"
    );
  }

  const token = parts[1];

  // Get issuer URL from environment
  const issuerUrl = process.env.CLERK_ISSUER_URL;
  if (!issuerUrl) {
    throw new AuthenticationError(
      "CLERK_ISSUER_URL not configured",
      "CONFIG_ERROR"
    );
  }

  // Decode header to get key ID
  let header: { alg: string; kid?: string };
  try {
    header = decodeJwtHeader(token);
  } catch {
    throw new AuthenticationError("Invalid JWT header", "INVALID_TOKEN");
  }

  // Verify algorithm
  if (header.alg !== "RS256") {
    throw new AuthenticationError(
      `Unsupported algorithm: ${header.alg}`,
      "INVALID_ALGORITHM"
    );
  }

  // Get the key ID
  const kid = header.kid;
  if (!kid) {
    throw new AuthenticationError("Missing key ID in JWT header", "MISSING_KID");
  }

  // Fetch JWKS and get the signing key
  const keys = await fetchJwks(issuerUrl);
  let publicKey = keys.get(kid);

  if (!publicKey) {
    // Key not found, might be rotated - try refreshing cache
    jwksCache = null;
    const refreshedKeys = await fetchJwks(issuerUrl);
    publicKey = refreshedKeys.get(kid);

    if (!publicKey) {
      throw new AuthenticationError(
        "Signing key not found",
        "KEY_NOT_FOUND"
      );
    }
  }

  // Verify signature
  const isValid = await verifyJwtSignature(token, publicKey);
  if (!isValid) {
    throw new AuthenticationError("Invalid token signature", "INVALID_SIGNATURE");
  }

  // Decode and validate payload
  let payload: ClerkJWTPayload;
  try {
    payload = decodeJwtPayload(token);
  } catch {
    throw new AuthenticationError("Invalid JWT payload", "INVALID_PAYLOAD");
  }

  // Validate issuer
  if (payload.iss !== issuerUrl) {
    throw new AuthenticationError(
      "Invalid token issuer",
      "INVALID_ISSUER"
    );
  }

  // Validate expiration
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp < now) {
    throw new AuthenticationError("Token has expired", "TOKEN_EXPIRED");
  }

  // Validate not-before (if present)
  if (payload.nbf && payload.nbf > now) {
    throw new AuthenticationError("Token is not yet valid", "TOKEN_NOT_YET_VALID");
  }

  // Return clerkUserId and role (default role to "user" if not present)
  return {
    clerkUserId: payload.sub,
    role: (payload as unknown as { role?: string }).role ?? "user",
  };
}
