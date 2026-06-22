import { useAuth } from "../lib/auth";

/** Placeholder home screen — Faz 1+ will replace this with the real menu
 * (hammaddeler, formüller, MultiBlend, ...) gated by user_menu_access. */
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
      <p style={{ color: "#888" }}>
        Menüler (hammaddeler, formüller, MultiBlend...) sonraki fazda buraya eklenecek.
      </p>
    </div>
  );
}
