import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { Material, NutrientDef } from "../lib/types";

const emptyForm: Material = {
  code: "",
  name: "",
  priceTL: null,
  isAvailable: true,
};

export default function Materials() {
  const [materials, setMaterials] = useState<Material[]>([]);
  const [nutrientDefs, setNutrientDefs] = useState<NutrientDef[]>([]);
  const [form, setForm] = useState<Material>(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [nutrientFilter, setNutrientFilter] = useState("");
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
  useEffect(() => {
    apiFetch<NutrientDef[]>("/nutrient-defs").then(setNutrientDefs).catch(() => {});
  }, []);

  const filteredDefs = useMemo(() => {
    const q = nutrientFilter.trim().toLocaleLowerCase("tr");
    if (!q) return nutrientDefs;
    return nutrientDefs.filter(
      (d) => d.displayName.toLocaleLowerCase("tr").includes(q) || d.key.toLocaleLowerCase("tr").includes(q)
    );
  }, [nutrientDefs, nutrientFilter]);

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

  function setNutrient(key: string, value: string) {
    setForm({ ...form, [key]: value === "" ? null : Number(value) });
  }

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 1000 }}>
      <p>
        <Link to="/">← Panel</Link>
      </p>
      <h1>Hammaddeler</h1>

      <form onSubmit={handleSubmit} style={{ margin: "16px 0" }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "end", marginBottom: 12 }}>
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
              value={(form.priceTL as number | null) ?? ""}
              onChange={(e) => setForm({ ...form, priceTL: e.target.value === "" ? null : Number(e.target.value) })}
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
        </div>

        <details open={!!editingId}>
          <summary style={{ cursor: "pointer", fontWeight: 600, margin: "8px 0" }}>
            Besin Değerleri ({nutrientDefs.length} alan) — genişletmek için tıklayın
          </summary>
          <input
            placeholder="Besin değeri ara (örn. lizin, kalsiyum, enerji...)"
            value={nutrientFilter}
            onChange={(e) => setNutrientFilter(e.target.value)}
            style={{ ...inputStyle, width: "100%", margin: "8px 0" }}
          />
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))",
              gap: 8,
              maxHeight: 400,
              overflowY: "auto",
              border: "1px solid #eee",
              padding: 8,
              borderRadius: 8,
            }}
          >
            {filteredDefs.map((def) => (
              <label key={def.key} style={{ fontSize: 13 }}>
                {def.displayName} {def.unit && `(${def.unit})`}
                <input
                  type="number"
                  step="any"
                  value={(form[def.key] as number | null) ?? ""}
                  onChange={(e) => setNutrient(def.key, e.target.value)}
                  style={{ ...inputStyle, width: "100%" }}
                />
              </label>
            ))}
          </div>
        </details>

        <div style={{ marginTop: 12 }}>
          <button type="submit">{editingId ? "Güncelle" : "Ekle"}</button>{" "}
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
        </div>
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
                <td>{(m.crudeProtein as number | null) ?? "-"}</td>
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
