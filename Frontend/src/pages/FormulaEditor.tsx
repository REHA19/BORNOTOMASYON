import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import { sendFormulaToFactory } from "../lib/factorySend";
import { newUUID } from "../lib/uuid";
import type { BFConstraint, BFIngredient, Formula, Material, NutrientDef } from "../lib/types";

function newIngredient(code: string, name: string): BFIngredient {
  return {
    id: newUUID(),
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

function newConstraint(def: NutrientDef): BFConstraint {
  return {
    id: newUUID(),
    nutrientKey: def.key,
    displayName: def.displayName,
    unit: def.unit,
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
  const [nutrientDefs, setNutrientDefs] = useState<NutrientDef[]>([]);
  const [pickCode, setPickCode] = useState("");
  const [pickNutrientKey, setPickNutrientKey] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSolving, setIsSolving] = useState(false);

  const [sendOpen, setSendOpen] = useState(false);
  const [customName, setCustomName] = useState("");
  const [customVersion, setCustomVersion] = useState("1");
  const [validDate, setValidDate] = useState("");
  const [comment, setComment] = useState("");
  const [activate, setActivate] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const [sendResult, setSendResult] = useState<string | null>(null);

  function load() {
    apiFetch<Formula>(`/formulas/${id}`).then(setFormula).catch((e) => setError(e instanceof ApiError ? e.message : "Yüklenemedi"));
  }

  useEffect(load, [id]);
  useEffect(() => {
    apiFetch<Material[]>("/materials").then(setMaterials).catch(() => {});
    apiFetch<NutrientDef[]>("/nutrient-defs").then(setNutrientDefs).catch(() => {});
  }, []);
  useEffect(() => {
    if (formula && !customName) setCustomName(formula.name);
  }, [formula]);

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
    const def = nutrientDefs.find((d) => d.key === pickNutrientKey);
    if (!def || formula!.constraints.some((c) => c.nutrientKey === def.key)) return;
    setFormula({ ...formula!, constraints: [...formula!.constraints, newConstraint(def)] });
    setPickNutrientKey("");
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

  async function sendToFactory() {
    setIsSending(true);
    setSendResult(null);
    try {
      await sendFormulaToFactory(formula!, { customName, customVersion, validDate, comment, activate });
      setSendResult("Fabrika sunucusuna başarıyla gönderildi.");
    } catch (err) {
      setSendResult(err instanceof Error ? err.message : "Gönderim başarısız.");
    } finally {
      setIsSending(false);
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
            <th>Fiyat (₺/ton)</th>
            <th>Min %</th>
            <th>Max %</th>
            <th>Sonuç %</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {/* En çok kullanılan hammadde en üstte — çözüm sonrası okunabilirlik için */}
          {formula.ingredients
            .map((ing, idx) => ({ ing, idx }))
            .sort((a, b) => b.ing.mixPct - a.ing.mixPct)
            .map(({ ing, idx }) => {
              const libraryPrice = materials.find((m) => m.code === ing.code)?.priceTL as number | null | undefined;
              return (
                <tr key={ing.id} style={{ borderBottom: "1px solid #eee" }}>
                  <td>{ing.code}</td>
                  <td>{ing.name}</td>
                  <td>
                    <input
                      type="number"
                      style={{ width: 90 }}
                      placeholder={libraryPrice != null ? String(libraryPrice) : ""}
                      value={ing.overridePriceTLPerTon ?? ""}
                      onChange={(e) =>
                        updateIngredient(idx, {
                          overridePriceTLPerTon: e.target.value === "" ? null : Number(e.target.value),
                        })
                      }
                    />
                  </td>
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
              );
            })}
        </tbody>
      </table>

      <h2>Besin Kısıtları</h2>
      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <select value={pickNutrientKey} onChange={(e) => setPickNutrientKey(e.target.value)}>
          <option value="">Besin değeri seçin...</option>
          {nutrientDefs.map((def) => (
            <option key={def.key} value={def.key}>
              {def.displayName} {def.unit && `(${def.unit})`}
            </option>
          ))}
        </select>
        <button onClick={addConstraint} disabled={!pickNutrientKey}>
          + Kısıt Ekle
        </button>
      </div>
      <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: 24 }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "1px solid #ccc" }}>
            <th>Besin Değeri</th>
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
                {con.displayName} {con.unit && `(${con.unit})`}
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
        {formula.lastSolve?.isFeasible && (
          <button onClick={() => setSendOpen((v) => !v)}>Sunucuya Gönder</button>
        )}
      </div>

      {formula.lastSolve && (
        <div style={{ marginTop: 24, padding: 16, background: formula.lastSolve.isFeasible ? "#eafaf1" : "#fdecea", borderRadius: 8 }}>
          <strong>{formula.lastSolve.isFeasible ? "Çözüm bulundu" : "Çözüm bulunamadı"}</strong>
          <p>{formula.lastSolve.message}</p>
          {formula.lastSolve.isFeasible && <p>Maliyet: {formula.lastSolve.costPerTon.toFixed(2)} ₺/ton</p>}
        </div>
      )}

      {sendOpen && (
        <div style={{ marginTop: 16, padding: 16, border: "1px solid #ddd", borderRadius: 8, maxWidth: 400 }}>
          <h3 style={{ marginTop: 0 }}>Fabrika Sunucusuna Gönder (192.168.2.77:5001)</h3>
          <p style={{ color: "#888", fontSize: 13 }}>
            Bu işlem yalnızca fabrika ağına (VPN dahil) bağlıyken çalışır.
          </p>
          <label style={fieldStyle}>
            İsim
            <input value={customName} onChange={(e) => setCustomName(e.target.value)} />
          </label>
          <label style={fieldStyle}>
            Versiyon
            <input value={customVersion} onChange={(e) => setCustomVersion(e.target.value)} />
          </label>
          <label style={fieldStyle}>
            Geçerlilik Tarihi
            <input type="date" value={validDate} onChange={(e) => setValidDate(e.target.value)} />
          </label>
          <label style={fieldStyle}>
            Not
            <input value={comment} onChange={(e) => setComment(e.target.value)} />
          </label>
          <label style={{ display: "flex", alignItems: "center", gap: 4, margin: "8px 0" }}>
            <input type="checkbox" checked={activate} onChange={(e) => setActivate(e.target.checked)} />
            Aktif olarak işaretle
          </label>
          <button onClick={sendToFactory} disabled={isSending || !customName.trim()}>
            {isSending ? "Gönderiliyor..." : "Gönder"}
          </button>
          {sendResult && <p style={{ marginTop: 8 }}>{sendResult}</p>}
        </div>
      )}
    </div>
  );
}

const fieldStyle: React.CSSProperties = { display: "block", margin: "8px 0" };
