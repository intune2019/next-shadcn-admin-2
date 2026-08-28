"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";

interface TenantContextValue {
  tenantId: string | null;
  matterId: string | null;
  setTenantId: (id: string | null) => void;
  setMatterId: (id: string | null) => void;
}

const TenantContext = createContext<TenantContextValue | null>(null);

const TENANT_KEY = "forensiq.tenantId";
const MATTER_KEY = "forensiq.matterId";

export function TenantProvider({ children }: { children: ReactNode }) {
  const [tenantId, setTenantIdState] = useState<string | null>(null);
  const [matterId, setMatterIdState] = useState<string | null>(null);

  useEffect(() => {
    setTenantIdState(localStorage.getItem(TENANT_KEY));
    setMatterIdState(localStorage.getItem(MATTER_KEY));
  }, []);

  function setTenantId(id: string | null) {
    setTenantIdState(id);
    if (id) localStorage.setItem(TENANT_KEY, id);
    else localStorage.removeItem(TENANT_KEY);
  }

  function setMatterId(id: string | null) {
    setMatterIdState(id);
    if (id) localStorage.setItem(MATTER_KEY, id);
    else localStorage.removeItem(MATTER_KEY);
  }

  return (
    <TenantContext.Provider value={{ tenantId, matterId, setTenantId, setMatterId }}>
      {children}
    </TenantContext.Provider>
  );
}

export function useTenant() {
  const ctx = useContext(TenantContext);
  if (!ctx) throw new Error("useTenant must be used within TenantProvider");
  return ctx;
}
