"use client";

import { useEffect, useState } from "react";
import { Select } from "@once-ui-system/core";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import type { RelationConfig } from "@/lib/resources/types";

/** Searchable picker over another resource's rows — replaces raw-UUID text entry for FK fields. */
export function RelationSelect({
  id,
  label,
  relation,
  required,
  value,
  onSelect,
}: {
  id: string;
  label: string;
  relation: RelationConfig;
  required?: boolean;
  value?: string;
  onSelect: (value: string) => void;
}) {
  const { matterId } = useTenant();
  const [options, setOptions] = useState<{ label: string; value: string }[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true);
      const supabase = createClient();
      let query = supabase
        .schema(relation.schema)
        .from(relation.table)
        .select(`${relation.valueKey}, ${relation.labelKey}`)
        .limit(200);
      if (relation.matterScoped) {
        if (!matterId) {
          setOptions([]);
          setLoading(false);
          return;
        }
        query = query.eq("matter_id", matterId);
      }
      const { data } = await query;
      if (cancelled) return;
      setOptions(
        ((data as unknown as Record<string, unknown>[]) ?? []).map((row) => ({
          value: String(row[relation.valueKey]),
          label: String(row[relation.labelKey] ?? row[relation.valueKey]),
        })),
      );
      setLoading(false);
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [relation, matterId]);

  return (
    <Select
      id={id}
      label={loading ? `${label} (loading…)` : label}
      required={required}
      options={options}
      value={value}
      onSelect={(v) => onSelect(v as string)}
    />
  );
}
