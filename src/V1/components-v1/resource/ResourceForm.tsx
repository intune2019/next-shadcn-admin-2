"use client";

import { useState, type FormEvent } from "react";
import {
  Column,
  Input,
  Textarea,
  NumberInput,
  DateInput,
  Select,
  Checkbox,
  Button,
  useToast,
} from "@once-ui-system/core";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import { createMatter } from "@/app/app/matters/actions";
import { RelationSelect } from "./RelationSelect";
import type { ResourceConfig } from "@/lib/resources/types";

export function ResourceForm({
  config,
  onCreated,
}: {
  config: ResourceConfig;
  onCreated?: () => void;
}) {
  const { addToast } = useToast();
  const { tenantId, matterId, setMatterId } = useTenant();
  const isMatterCreate = config.schema === "core" && config.table === "matters";
  const [values, setValues] = useState<Record<string, unknown>>(() => {
    const initial: Record<string, unknown> = {};
    for (const f of config.fields) {
      if (f.defaultValue !== undefined) initial[f.key] = f.defaultValue;
    }
    return initial;
  });
  const [submitting, setSubmitting] = useState(false);

  function setField(key: string, value: unknown) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();

    if (isMatterCreate) {
      if (!tenantId) {
        addToast({ variant: "danger", message: "Set an active tenant first (top bar)." });
        return;
      }
      setSubmitting(true);
      const result = await createMatter({
        tenantId,
        matterName: (values.matter_name as string) ?? "",
        matterType: (values.matter_type as string) ?? "",
        confidentiality: values.confidentiality as string | undefined,
      });
      setSubmitting(false);
      if ("error" in result) {
        addToast({ variant: "danger", message: result.error });
        return;
      }
      addToast({ variant: "success", message: `Matter ${result.matterNumber} created.` });
      setMatterId(result.id);
      setValues({});
      onCreated?.();
      return;
    }

    const missingAuto = config.fields.find((f) =>
      f.auto === "tenant_id" ? !tenantId : f.auto === "matter_id" ? !matterId : false,
    );
    if (missingAuto) {
      addToast({
        variant: "danger",
        message: `Set an active ${missingAuto.auto === "tenant_id" ? "tenant" : "matter"} first (top bar).`,
      });
      return;
    }

    const payload: Record<string, unknown> = {};
    for (const f of config.fields) {
      if (f.auto === "tenant_id") {
        payload[f.key] = tenantId;
        continue;
      }
      if (f.auto === "matter_id") {
        payload[f.key] = matterId;
        continue;
      }
      const v = values[f.key];
      if (v === undefined || v === "") continue;
      payload[f.key] = v;
    }

    setSubmitting(true);
    const supabase = createClient();
    const { error } = await supabase.schema(config.schema).from(config.table).insert(payload);
    setSubmitting(false);

    if (error) {
      addToast({ variant: "danger", message: error.message });
      return;
    }
    addToast({ variant: "success", message: `${config.label} created.` });
    setValues({});
    onCreated?.();
  }

  return (
    <Column as="form" onSubmit={handleSubmit} gap="16" fillWidth>
      {config.fields
        .filter((f) => !f.auto)
        .map((f) => {
          const description = f.help;
          switch (f.type) {
            case "textarea":
              return (
                <Textarea
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  required={f.required}
                  description={description}
                  value={(values[f.key] as string) ?? ""}
                  onChange={(e) => setField(f.key, e.target.value)}
                />
              );
            case "number":
              return (
                <NumberInput
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  required={f.required}
                  description={description}
                  value={values[f.key] as number}
                  onChange={(v) => setField(f.key, v)}
                />
              );
            case "date":
              return (
                <DateInput
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  value={values[f.key] as Date}
                  onChange={(d) => setField(f.key, d.toISOString())}
                />
              );
            case "select":
              return (
                <Select
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  required={f.required}
                  description={description}
                  options={f.options ?? []}
                  value={values[f.key] as string}
                  onSelect={(v) => setField(f.key, v as string)}
                />
              );
            case "relation":
              if (!f.relation) return null;
              return (
                <RelationSelect
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  required={f.required}
                  relation={f.relation}
                  value={values[f.key] as string}
                  onSelect={(v) => setField(f.key, v)}
                />
              );
            case "checkbox":
              return (
                <Checkbox
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  isChecked={Boolean(values[f.key])}
                  onToggle={() => setField(f.key, !values[f.key])}
                />
              );
            default:
              return (
                <Input
                  key={f.key}
                  id={f.key}
                  label={f.label}
                  required={f.required}
                  description={description}
                  value={(values[f.key] as string) ?? ""}
                  onChange={(e) => setField(f.key, e.target.value)}
                />
              );
          }
        })}
      <Button type="submit" loading={submitting} data-border="sharp">
        Create {config.label}
      </Button>
    </Column>
  );
}
