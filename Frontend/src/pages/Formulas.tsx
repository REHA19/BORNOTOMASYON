import { useEffect, useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { Formula } from "../lib/types";

export default function Formulas() {
  const [formulas, setFormulas] = useState<Formula[]>([]);
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  function load() {
    apiFetch<Formula[]>("/formulas").then(setFormulas).catch(() => {});
  }

  useEffect(load, []);

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      const formula = await apiFetch<Formula>("/formulas", {
        method: "POST",
        body: JSON.stringify({ code, name }),
      });
      navigate(`/formulas/${formula.id}`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Oluşturulamadı");
    }
  }

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 700 }}>
      <p>
        <Link to="/">← Panel</Link>
      </p>
      <h1>Formüller</h1>

      <form onSubmit={handleCreate} style={{ display: "flex", gap: 8, margin: "16px 0" }}>
        <input placeholder="Kod" required value={code} onChange={(e) => setCode(e.target.value)} />
        <input placeholder="İsim" required value={name} onChange={(e) => setName(e.target.value)} />
        <button type="submit">Yeni Formül</button>
      </form>
      {error && <p style={{ color: "#c0392b" }}>{error}</p>}

      <ul style={{ listStyle: "none", padding: 0 }}>
        {formulas.map((f) => (
          <li key={f.id} style={{ padding: "8px 0", borderBottom: "1px solid #eee" }}>
            <Link to={`/formulas/${f.id}`}>
              <strong>{f.code}</strong> — {f.name}
            </Link>
            {f.lastSolve && (
              <span style={{ color: "#888", marginLeft: 8 }}>
                ({f.lastSolve.costPerTon.toFixed(0)} ₺/ton)
              </span>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
