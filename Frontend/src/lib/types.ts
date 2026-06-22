// Mirrors a subset of Backend/Sources/App/Models/FeedIngredient.swift —
// the full model has ~142 nutrient fields; only the ones editable from this
// first web UI pass are listed here. Extra server fields pass through
// untouched since these are just TS shapes, not runtime validators.
export interface Material {
  id?: string;
  code: string;
  name: string;
  priceTL: number | null;
  isAvailable: boolean;
  crudeProtein?: number | null;
  crudeFat?: number | null;
  crudeFiber?: number | null;
  dryMatter?: number | null;
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
