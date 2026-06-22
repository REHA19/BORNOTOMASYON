import { Link } from "react-router-dom";
import { useAuth } from "../lib/auth";

export default function Dashboard() {
  const { user, logout } = useAuth();

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>BORN OTOMASYON</h1>
        <button onClick={logout}>Çıkış Yap</button>
      </div>
      <p>
        Giriş yapan kullanıcı: <strong>{user?.displayName}</strong> ({user?.username})
        {user?.isAdmin && " — Admin"}
      </p>

      <nav style={{ display: "flex", gap: 16, marginTop: 24 }}>
        <Link to="/materials" style={navLinkStyle}>
          Hammaddeler
        </Link>
        <Link to="/formulas" style={navLinkStyle}>
          Formüller
        </Link>
      </nav>
      <p style={{ color: "#888", marginTop: 24 }}>
        MultiBlend, fiyat takibi, raporlar gibi diğer menüler sonraki fazlarda eklenecek.
      </p>
    </div>
  );
}

const navLinkStyle: React.CSSProperties = {
  padding: "10px 16px",
  borderRadius: 8,
  background: "#1a5e9a",
  color: "#fff",
  textDecoration: "none",
  fontWeight: 600,
};
