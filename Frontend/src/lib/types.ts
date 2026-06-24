export interface NutrientDef {
  key: string;
  displayName: string;
  unit: string;
}

// Core fields are typed; the ~104 nutrient fields (dryMatter, crudeProtein,
// calcium, lysine, ...) are accessed dynamically via the index signature,
// driven by NutrientDef keys fetched from GET /api/nutrient-defs — mirrors
// Backend/Sources/App/Models/FeedIngredient.swift without duplicating its
// full field list here.
export interface Material {
  id?: string;
  code: string;
  name: string;
  priceTL: number | null;
  isAvailable: boolean;
  [nutrientKey: string]: string | number | boolean | null | undefined;
}

export interface BFIngredient {
  id: string;
  code: string;
  name: string;
  isActive: boolean;
  hasStock: boolean;
  minPct: number;
  maxPct: number;
  mixPct: number;
  productionMixPct: number;
  previousMixPct: number;
  overridePriceTLPerTon?: number | null;
}

export interface BFConstraint {
  id: string;
  nutrientKey: string;
  displayName: string;
  unit: string;
  isActive: boolean;
  showInResult: boolean;
  minValue?: number | null;
  maxValue?: number | null;
  currentValue?: number | null;
  previousValue?: number | null;
  productionValue?: number | null;
}

export interface BFSolveResult {
  percentagesByCode: Record<string, number>;
  costPerTon: number;
  nutrientValues: Record<string, number>;
  isFeasible: boolean;
  message: string;
  reducedCosts: Record<string, number>;
  costRangeIncreases: Record<string, number>;
  shadowPricesMin: Record<string, number>;
  shadowPricesMax: Record<string, number>;
}

export interface BFCombination {
  id: string;
  slot: number;
  ingredientCodes: string[];
  minKg?: number | null;
  maxKg?: number | null;
}

export interface MultiBlendFormulaEntry {
  code: string;
  name: string;
  tons: number;
  liveCostPerTon: number | null;
  snapshotCostPerTon: number | null;
  snapshotTons: number | null;
}

export interface MultiBlendGroup {
  id: string;
  name: string;
  orderIndex: number;
  version: number;
  productionSnapshotAt: string | null;
  stokYokCodes: string[];
  monthlyIngLimits: Record<string, { minTons?: number | null; maxTons?: number | null }>;
  entries: MultiBlendFormulaEntry[];
}

export interface Formula {
  id: string;
  code: string;
  name: string;
  totalKg: number;
  recordedCostTL: number;
  version: number;
  ingredients: BFIngredient[];
  constraints: BFConstraint[];
  combinations: BFCombination[];
  lastSolve?: BFSolveResult | null;
}
