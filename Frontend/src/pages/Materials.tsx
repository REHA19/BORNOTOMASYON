import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { Material } from "../lib/types";

const emptyForm: Material = {
  code: "",
  name: "",
  priceTL: null,
  isAvailable: true,
  crudeProtein: null,
};

export default function Materials() {
  const [materials, setMaterials] = useState<Material[]>([]);
  const [form, setForm] = useState<Material>(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  function load() {
    setIsLoading(true);
    apiFetch<Material[]>("/materials")
      .then(setMaterials)
      .catch((err) => setError(err instanceof ApiError ? err.message : "Yüklenemedi"))
      .finally(() => setIsLoading(false));
  }

  useEffect(load, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      if (editingId) {
        await apiFetch(`/materials/${editingId}`, { method: "PUT", body: JSON.stringify(form) });
      } else {
        await apiFetch("/materials", { method: "POST", body: JSON.stringify(form) });
      }
      setForm(emptyForm);
      setEditingId(null);
      load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Kaydedilemedi");
    }
  }

  function startEdit(m: Material) {
    setForm(m);
    setEditingId(m.id ?? null);
  }

  async function handleDelete(id: string) {
    if (!confirm("Bu hammaddeyi silmek istediğinize emin misiniz?")) return;
    try {
      await apiFetch(`/materials/${id}`, { method: "DELETE" });
      load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Silinemedi");
    }
  }

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 900 }}>
      <p>
        <Link to="/">← Panel</Link>
      </p>
      <h1>Hammaddeler</h1>

      <form onSubmit={handleSubmit} style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "16px 0", alignItems: "end" }}>
        <label>
          Kod
          <input required value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} style={inputStyle} />
        </label>
        <label>
          İsim
          <input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} style={inputStyle} />
        </label>
        <label>
          Fiyat (₺/ton)
          <input
            type="number"
            value={form.priceTL ?? ""}
            onChange={(e) => setForm({ ...form, priceTL: e.target.value === "" ? null : Number(e.target.value) })}
            style={inputStyle}
          />
        </label>
        <label>
          Ham Protein (%)
          <input
            type="number"
            value={form.crudeProtein ?? ""}
            onChange={(e) => setForm({ ...form, crudeProtein: e.target.value === "" ? null : Number(e.target.value) })}
            style={inputStyle}
          />
        </label>
        <label style={{ display: "flex", alignItems: "center", gap: 4 }}>
          <input
            type="checkbox"
            checked={form.isAvailable}
            onChange={(e) => setForm({ ...form, isAvailable: e.target.checked })}
          />
          Stokta var
        </label>
        <button type="submit">{editingId ? "Güncelle" : "Ekle"}</button>
        {editingId && (
          <button
            type="button"
            onClick={() => {
              setForm(emptyForm);
              setEditingId(null);
            }}
          >
            İptal
          </button>
        )}
      </form>

      {error && <p style={{ color: "#c0392b" }}>{error}</p>}
      {isLoading ? (
        <p>Yükleniyor...</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "1px solid #ccc" }}>
              <th>Kod</th>
              <th>İsim</th>
              <th>Fiyat (₺/ton)</th>
              <th>Ham Protein</th>
              <th>Stokta</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {materials.map((m) => (
              <tr key={m.id} style={{ borderBottom: "1px solid #eee" }}>
                <td>{m.code}</td>
                <td>{m.name}</td>
                <td>{m.priceTL ?? "-"}</td>
                <td>{m.crudeProtein ?? "-"}</td>
                <td>{m.isAvailable ? "Evet" : "Hayır"}</td>
                <td>
                  <button onClick={() => startEdit(m)}>Düzenle</button>{" "}
                  <button onClick={() => m.id && handleDelete(m.id)}>Sil</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

const inputStyle: React.CSSProperties = { display: "block", padding: 6, marginTop: 2 };
