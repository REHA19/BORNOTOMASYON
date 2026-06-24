import { useEffect, useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { MultiBlendGroup } from "../lib/types";

export default function MultiBlends() {
  const [groups, setGroups] = useState<MultiBlendGroup[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  function load() {
    apiFetch<MultiBlendGroup[]>("/multiblend").then(setGroups).catch(() => {});
  }

  useEffect(load, []);

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      const group = await apiFetch<MultiBlendGroup>("/multiblend", { method: "POST", body: JSON.stringify({ name }) });
      navigate(`/multiblend/${group.id}`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Oluşturulamadı");
    }
  }

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 700 }}>
      <p>
        <Link to="/">← Panel</Link>
      </p>
      <h1>MultiBlend Grupları</h1>

      <form onSubmit={handleCreate} style={{ display: "flex", gap: 8, margin: "16px 0" }}>
        <input placeholder="Grup adı" required value={name} onChange={(e) => setName(e.target.value)} />
        <button type="submit">Yeni Grup</button>
      </form>
      {error && <p style={{ color: "#c0392b" }}>{error}</p>}

      <ul style={{ listStyle: "none", padding: 0 }}>
        {groups.map((g) => (
          <li key={g.id} style={{ padding: "8px 0", borderBottom: "1px solid #eee" }}>
            <Link to={`/multiblend/${g.id}`}>
              <strong>{g.name}</strong>
            </Link>
            <span style={{ color: "#888", marginLeft: 8 }}>({g.entries.length} formül)</span>
            {g.productionSnapshotAt && <span style={{ color: "#2a7", marginLeft: 8 }}>Üretime kaydedildi</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}
