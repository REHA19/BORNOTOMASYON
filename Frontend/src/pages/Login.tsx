import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../lib/auth";
import { ApiError } from "../lib/api";

export default function Login() {
  const { login, isLoading } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await login(username, password);
      navigate("/");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Giriş başarısız");
    }
  }

  return (
    <div style={styles.page}>
      <form onSubmit={handleSubmit} style={styles.card}>
        <h1 style={styles.title}>BORN OTOMASYON</h1>
        <p style={styles.subtitle}>Web Paneli Girişi</p>

        <label style={styles.label}>
          Kullanıcı Adı
          <input
            style={styles.input}
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
            required
          />
        </label>

        <label style={styles.label}>
          Şifre
          <input
            style={styles.input}
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>

        {error && <p style={styles.error}>{error}</p>}

        <button style={styles.button} type="submit" disabled={isLoading}>
          {isLoading ? "Giriş yapılıyor..." : "Giriş Yap"}
        </button>
      </form>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    minHeight: "100vh",
    background: "#f4f5f7",
    fontFamily: "system-ui, sans-serif",
  },
  card: {
    display: "flex",
    flexDirection: "column",
    gap: 12,
    width: 320,
    padding: 32,
    borderRadius: 12,
    background: "#fff",
    boxShadow: "0 4px 24px rgba(0,0,0,0.08)",
  },
  title: { margin: 0, fontSize: 22, fontWeight: 700 },
  subtitle: { margin: "0 0 12px", color: "#666", fontSize: 14 },
  label: { display: "flex", flexDirection: "column", gap: 4, fontSize: 13, color: "#333" },
  input: { padding: "8px 10px", borderRadius: 8, border: "1px solid #ddd", fontSize: 14 },
  error: { color: "#c0392b", fontSize: 13, margin: 0 },
  button: {
    marginTop: 8,
    padding: "10px 14px",
    borderRadius: 8,
    border: "none",
    background: "#1a5e9a",
    color: "#fff",
    fontWeight: 600,
    cursor: "pointer",
  },
};
