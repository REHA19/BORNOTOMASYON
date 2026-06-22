import type { Formula } from "./types";

// Exact contract from the iOS app's SendFormulaSheet.swift / FormulaDetailService —
// the factory's tartım/silo control server at 192.168.2.77:5001 only understands
// this PascalCase shape. It's a local-network address; the browser must be on the
// factory VPN/LAN to reach it — our cloud backend cannot proxy this.
const FACTORY_BASE_URL = "http://192.168.2.77:5001";

interface FactorySendOptions {
  customName: string;
  customVersion: string;
  validDate?: string; // yyyy-MM-dd from a date input
  comment: string;
  activate: boolean;
}

interface FactoryResponse {
  Success: boolean;
  Message?: string;
}

export async function sendFormulaToFactory(formula: Formula, opts: FactorySendOptions): Promise<void> {
  const activeIngredients = formula.ingredients.filter((i) => i.isActive);

  const body = {
    ProductCode: formula.code,
    ProductName: formula.name,
    CustomName: opts.customName,
    CustomVersion: opts.customVersion,
    ValidDate: opts.validDate ? new Date(opts.validDate).toISOString() : null,
    TotalAmount: formula.totalKg,
    Comment: opts.comment,
    Activate: opts.activate,
    Details: activeIngredients.map((ing, idx) => ({
      MaterialCode: ing.code,
      MaterialName: ing.name,
      RowNo: idx + 1,
      Amount: (formula.totalKg * ing.mixPct) / 100,
      IsAdditive: false,
    })),
  };

  let res: Response;
  try {
    res = await fetch(`${FACTORY_BASE_URL}/api/CreateNewFormulaFromApp`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new Error(
      "Fabrika sunucusuna ulaşılamadı (192.168.2.77:5001) — VPN bağlantınızın açık olduğundan emin olun."
    );
  }

  if (!res.ok) {
    throw new Error(`Sunucu hatası: HTTP ${res.status}`);
  }

  const data: FactoryResponse = await res.json();
  if (!data.Success) {
    throw new Error(data.Message ?? "Fabrika sunucusu gönderimi reddetti.");
  }
}
