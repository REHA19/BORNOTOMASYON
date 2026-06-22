const TOKEN_KEY = "born_otomasyon_token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY);
}

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** All requests go through Vite's /api proxy (vite.config.ts) → backend's configurable base URL (Plan §0). */
export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers: HeadersInit = {
    "Content-Type": "application/json",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...options.headers,
  };

  const res = await fetch(`/api${path}`, { ...options, headers });

  if (!res.ok) {
    const body = await res.json().catch(() => ({ reason: res.statusText }));
    throw new ApiError(res.status, body.reason ?? "Bilinmeyen hata");
  }

  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}
