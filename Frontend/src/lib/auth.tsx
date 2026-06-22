import { createContext, useContext, useState, useCallback, useEffect, type ReactNode } from "react";
import { apiFetch, setToken, clearToken, getToken } from "./api";

export interface UserPublic {
  id: string;
  username: string;
  displayName: string;
  isAdmin: boolean;
}

interface AuthContextValue {
  user: UserPublic | null;
  isLoading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<UserPublic | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // On reload, re-hydrate the user from a previously stored token.
  useEffect(() => {
    if (!getToken()) return;
    apiFetch<UserPublic>("/auth/me")
      .then(setUser)
      .catch(() => clearToken());
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    setIsLoading(true);
    try {
      const result = await apiFetch<{ token: string; user: UserPublic }>("/auth/login", {
        method: "POST",
        body: JSON.stringify({ username, password }),
      });
      setToken(result.token);
      setUser(result.user);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const logout = useCallback(() => {
    clearToken();
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider value={{ user, isLoading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

export function hasStoredToken(): boolean {
  return getToken() !== null;
}
