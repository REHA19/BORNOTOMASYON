import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { BFConstraint, BFIngredient, Formula, Material } from "../lib/types";

function newIngredient(code: string, name: string): BFIngredient {
  return {
    id: crypto.randomUUID(),
    code,
    name,
    isActive: true,
    hasStock: true,
    minPct: 0,
    maxPct: 100,
    mixPct: 0,
    productionMixPct: 0,
    previousMixPct: 0,
  };
}

function newConstraint(): BFConstraint {
  return {
    id: crypto.randomUUID(),
    nutrientKey: "crudeProtein",
    displayName: "Ham Protein",
    unit: "%",
    isActive: true,
    showInResult: true,
    minValue: null,
    maxValue: null,
  };
}

export default function FormulaEditor() {
  const { id } = useParams<{ id: string }>();
  const [formula, setFormula] = useState<Formula | null>(null);
  const [materials, setMaterials] = useState<Material[]>([]);
  const [pickCode, setPickCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSolving, setIsSolving] = useState(false);

  function load() {
    apiFetch<Formula>(`/formulas/${id}`).then(setFormula).catch((e) => setError(e instanceof ApiError ? e.message : "Yüklenemedi"));
  }

  useEffect(load, [id]);
  useEffect(() => {
    apiFetch<Material[]>("/materials").then(setMaterials).catch(() => {});
  }, []);

  if (!formula) return <div style={{ padding: 32 }}>{error ?? "Yükleniyor..."}</div>;

  function addIngredient() {
    const mat = materials.find((m) => m.code === pickCode);
    if (!mat || formula!.ingredients.some((i) => i.code === mat.code)) return;
    setFormula({ ...formula!, ingredients: [...formula!.ingredients, newIngredient(mat.code, mat.name)] });
    setPickCode("");
  }

  function updateIngredient(idx: number, patch: Partial<BFIngredient>) {
    const next = [...formula!.ingredients];
    next[idx] = { ...next[idx], ...patch };
    setFormula({ ...formula!, ingredients: next });
  }

  function removeIngredient(idx: number) {
    setFormula({ ...formula!, ingredients: formula!.ingredients.filter((_, i) => i !== idx) });
  }

  function addConstraint() {
    setFormula({ ...formula!, constraints: [...formula!.constraints, newConstraint()] });
  }

  function updateConstraint(idx: number, patch: Partial<BFConstraint>) {
    const next = [...formula!.constraints];
    next[idx] = { ...next[idx], ...patch };
    setFormula({ ...formula!, constraints: next });
  }

  function removeConstraint(idx: number) {
    setFormula({ ...formula!, constraints: formula!.constraints.filter((_, i) => i !== idx) });
  }

  async function save() {
    setError(null);
    try {
      const updated = await apiFetch<Formula>(`/formulas/${id}`, {
        method: "PUT",
        body: JSON.stringify({
          version: formula!.version,
          ingredients: formula!.ingredients,
          constraints: formula!.constraints,
          combinations: formula!.combinations ?? [],
        }),
      });
      setFormula(updated);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Kaydedilemedi");
    }
  }

  async function solve() {
    setIsSolving(true);
    setError(null);
    try {
      await save();
      const result = await apiFetch<Formula>(`/formulas/${id}/solve`, { method: "POST" });
      setFormula(result);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Çözülemedi");
    } finally {
      setIsSolving(false);
    }
  }

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 900 }}>
      <p>
        <Link to="/formulas">← Formüller</Link>
      </p>
      <h1>
        {formula.code} — {formula.name}
      </h1>

      <h2>Hammaddeler</h2>
      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <select value={pickCode} onChange={(e) => setPickCode(e.target.value)}>
          <option value="">Hammadde seçin...</option>
          {materials.map((m) => (
            <option key={m.code} value={m.code}>
              {m.code} — {m.name}
            </option>
          ))}
        </select>
        <button onClick={addIngredient} disabled={!pickCode}>
          Ekle
        </button>
      </div>
      <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: 24 }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "1px solid #ccc" }}>
            <th>Kod</th>
            <th>İsim</th>
            <th>Min %</th>
            <th>Max %</th>
            <th>Sonuç %</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {formula.ingredients.map((ing, idx) => (
            <tr key={ing.id} style={{ borderBottom: "1px solid #eee" }}>
              <td>{ing.code}</td>
              <td>{ing.name}</td>
              <td>
                <input
                  type="number"
                  style={{ width: 70 }}
                  value={ing.minPct}
                  onChange={(e) => updateIngredient(idx, { minPct: Number(e.target.value) })}
                />
              </td>
              <td>
                <input
                  type="number"
                  style={{ width: 70 }}
                  value={ing.maxPct}
                  onChange={(e) => updateIngredient(idx, { maxPct: Number(e.target.value) })}
                />
              </td>
              <td>{ing.mixPct.toFixed(2)}</td>
              <td>
                <button onClick={() => removeIngredient(idx)}>Çıkar</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Besin Kısıtları</h2>
      <button onClick={addConstraint} style={{ marginBottom: 8 }}>
        + Kısıt Ekle
      </button>
      <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: 24 }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "1px solid #ccc" }}>
            <th>Besin Anahtarı</th>
            <th>Min</th>
            <th>Max</th>
            <th>Sonuç</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {formula.constraints.map((con, idx) => (
            <tr key={con.id} style={{ borderBottom: "1px solid #eee" }}>
              <td>
                <input
                  value={con.nutrientKey}
                  onChange={(e) => updateConstraint(idx, { nutrientKey: e.target.value, displayName: e.target.value })}
                  placeholder="örn: crudeProtein"
                />
              </td>
              <td>
                <input
                  type="number"
                  style={{ width: 70 }}
                  value={con.minValue ?? ""}
                  onChange={(e) => updateConstraint(idx, { minValue: e.target.value === "" ? null : Number(e.target.value) })}
                />
              </td>
              <td>
                <input
                  type="number"
                  style={{ width: 70 }}
                  value={con.maxValue ?? ""}
                  onChange={(e) => updateConstraint(idx, { maxValue: e.target.value === "" ? null : Number(e.target.value) })}
                />
              </td>
              <td>{con.currentValue?.toFixed(2) ?? "-"}</td>
              <td>
                <button onClick={() => removeConstraint(idx)}>Çıkar</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {error && <p style={{ color: "#c0392b" }}>{error}</p>}

      <div style={{ display: "flex", gap: 8 }}>
        <button onClick={save}>Kaydet</button>
        <button onClick={solve} disabled={isSolving}>
          {isSolving ? "Çözülüyor..." : "Çöz"}
        </button>
      </div>

      {formula.lastSolve && (
        <div style={{ marginTop: 24, padding: 16, background: formula.lastSolve.isFeasible ? "#eafaf1" : "#fdecea", borderRadius: 8 }}>
          <strong>{formula.lastSolve.isFeasible ? "Çözüm bulundu" : "Çözüm bulunamadı"}</strong>
          <p>{formula.lastSolve.message}</p>
          {formula.lastSolve.isFeasible && <p>Maliyet: {formula.lastSolve.costPerTon.toFixed(2)} ₺/ton</p>}
        </div>
      )}
    </div>
  );
}
