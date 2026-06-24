import { Navigate, Route, BrowserRouter, Routes } from "react-router-dom";
import { AuthProvider, useAuth, hasStoredToken } from "./lib/auth";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Materials from "./pages/Materials";
import Formulas from "./pages/Formulas";
import FormulaEditor from "./pages/FormulaEditor";
import MultiBlends from "./pages/MultiBlends";
import MultiBlendDetail from "./pages/MultiBlendDetail";
import type { ReactNode } from "react";

function ProtectedRoute({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  if (!user && !hasStoredToken()) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Dashboard />
              </ProtectedRoute>
            }
          />
          <Route
            path="/materials"
            element={
              <ProtectedRoute>
                <Materials />
              </ProtectedRoute>
            }
          />
          <Route
            path="/formulas"
            element={
              <ProtectedRoute>
                <Formulas />
              </ProtectedRoute>
            }
          />
          <Route
            path="/formulas/:id"
            element={
              <ProtectedRoute>
                <FormulaEditor />
              </ProtectedRoute>
            }
          />
          <Route
            path="/multiblend"
            element={
              <ProtectedRoute>
                <MultiBlends />
              </ProtectedRoute>
            }
          />
          <Route
            path="/multiblend/:id"
            element={
              <ProtectedRoute>
                <MultiBlendDetail />
              </ProtectedRoute>
            }
          />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
