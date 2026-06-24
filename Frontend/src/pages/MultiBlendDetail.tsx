import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { apiFetch, ApiError } from "../lib/api";
import type { Formula, MultiBlendGroup } from "../lib/types";

export default function MultiBlendDetail() {
  const { id } = useParams<{ id: string }>();
  const [group, setGroup] = useState<MultiBlendGroup | null>(null);
  const [formulas, setFormulas] = useState<Formula[]>([]);
  const [pickCode, setPickCode] = useState("");
  const [tonsByCode, setTonsByCode] = useState<Record<string, number>>({});
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  function load() {
    apiFetch<MultiBlendGroup>(`/multiblend/${id}`)
      .then((g) => {
        setGroup(g);
        setTonsByCode(Object.fromEntries(g.entries.map((e) => [e.code, e.tons])));
      })
      .catch((e) => setError(e instanceof ApiError ? e.message : "Yüklenemedi"));
  }

  useEffect(load, [id]);
  useEffect(() => {
    apiFetch<Formula[]>("/formulas").then(setFormulas).catch(() => {});
  }, []);

  if (!group) return <div style={{ padding: 32 }}>{error ?? "Yükleniyor..."}</div>;

  const availableFormulas = formulas.filter((f) => !group.entries.some((e) => e.code === f.code));

  async function persist(formulaCodes: string[], tons: Record<string, number>) {
    setError(null);
    try {
      const updated = await apiFetch<MultiBlendGroup>(`/multiblend/${id}`, {
        method: "PUT",
        body: JSON.stringify({
          version: group!.version,
          formulaCodes,
          productionTons: tons,
          monthlyIngLimits: group!.monthlyIngLimits,
          stokYokCodes: group!.stokYokCodes,
        }),
      });
      setGroup(updated);
      setTonsByCode(Object.fromEntries(updated.entries.map((e) => [e.code, e.tons])));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Kaydedilemedi");
    }
  }

  function addFormula() {
    const formula = availableFormulas.find((f) => f.code === pickCode);
    if (!formula) return;
    const codes = [...group!.entries.map((e) => e.code), formula.code];
    persist(codes, { ...tonsByCode, [formula.code]: tonsByCode[formula.code] ?? 0 });
    setPickCode("");
  }

  function removeFormula(code: string) {
    const codes = group!.entries.map((e) => e.code).filter((c) => c !== code);
    persist(codes, tonsByCode);
  }

  function saveTons(code: string, value: number) {
    const next = { ...tonsByCode, [code]: value };
    setTonsByCode(next);
    persist(group!.entries.map((e) => e.code), next);
  }

  async function saveProduction() {
    setIsSaving(true);
    setError(null);
    try {
      const updated = await apiFetch<MultiBlendGroup>(`/multiblend/${id}/save-production`, { method: "POST" });
      setGroup(updated);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Üretime kaydedilemedi");
    } finally {
      setIsSaving(false);
    }
  }

  const totalTL = group.entries.reduce((sum, e) => sum + (e.liveCostPerTon ?? 0) * e.tons, 0);

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", padding: 32, maxWidth: 900 }}>
      <p>
        <Link to="/multiblend">← MultiBlend Grupları</Link>
      </p>
      <h1>{group.name}</h1>
      {group.productionSnapshotAt && (
        <p style={{ color: "#2a7" }}>
          Son üretime kayıt: {new Date(group.productionSnapshotAt).toLocaleString("tr-TR")}
        </p>
      )}

      <div style={{ display: "flex", gap: 8, marginBottom: 8 }}>
        <select value={pickCode} onChange={(e) => setPickCode(e.target.value)}>
          <option value="">Formül seçin...</option>
          {availableFormulas.map((f) => (
            <option key={f.code} value={f.code}>
              {f.code} — {f.name}
            </option>
          ))}
        </select>
        <button onClick={addFormula} disabled={!pickCode}>
          Ekle
        </button>
      </div>

      {error && <p style={{ color: "#c0392b" }}>{error}</p>}

      <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: 16 }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "1px solid #ccc" }}>
            <th>Formül</th>
            <th>Aylık Ton</th>
            <th>Canlı Maliyet (₺/ton)</th>
            <th>Tutar (₺)</th>
            <th>Kayıtlı Maliyet (Üretim)</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {group.entries.map((e) => (
            <tr key={e.code} style={{ borderBottom: "1px solid #eee" }}>
              <td>
                {e.code} — {e.name}
              </td>
              <td>
                <input
                  type="number"
                  style={{ width: 90 }}
                  value={tonsByCode[e.code] ?? 0}
                  onChange={(ev) => saveTons(e.code, Number(ev.target.value))}
                />
              </td>
              <td>{e.liveCostPerTon?.toFixed(2) ?? "-"}</td>
              <td>{e.liveCostPerTon ? ((e.liveCostPerTon * e.tons).toFixed(2)) : "-"}</td>
              <td>
                {e.snapshotCostPerTon != null
                  ? `${e.snapshotCostPerTon.toFixed(2)} ₺/ton (${e.snapshotTons} ton)`
                  : "-"}
              </td>
              <td>
                <button onClick={() => removeFormula(e.code)}>Çıkar</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <p>
        <strong>Toplam (canlı): {totalTL.toFixed(2)} ₺</strong>
      </p>

      <button onClick={saveProduction} disabled={isSaving}>
        {isSaving ? "Kaydediliyor..." : "Üretime Kaydet"}
      </button>
    </div>
  );
}
