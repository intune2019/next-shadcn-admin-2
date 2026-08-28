"use client";

import type { ResourceConfig } from "@/lib/resources/types";
import { createClient } from "@/lib/supabase/client";
import {
  Button,
  Checkbox,
  Column,
  Heading,
  Input,
  Line,
  NumberInput,
  Row,
  Select,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { RelationSelect } from "./RelationSelect";

function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

export function ResourceDetail({ config, id }: { config: ResourceConfig; id: string }) {
  const { addToast } = useToast();
  const [row, setRow] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [values, setValues] = useState<Record<string, unknown>>({});
  const [submitting, setSubmitting] = useState(false);
  const [findingSources, setFindingSources] = useState<
    {
      is_contrary: boolean;
      facts: {
        id: string;
        statement: string;
        fact_type: string | null;
        confidence: string | null;
      }[];
    }[]
  >([]);
  const [linkFactId, setLinkFactId] = useState("");
  const [linkContrary, setLinkContrary] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [generatedRows, setGeneratedRows] = useState<Record<string, unknown>[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { data, error } = await supabase
      .schema(config.schema)
      .from(config.table)
      .select("*")
      .eq("id", id)
      .single();
    setLoading(false);
    if (error) {
      setError(error.message);
      return;
    }
    setRow(data as Record<string, unknown>);
    const initial: Record<string, unknown> = {};
    for (const f of config.updateFields ?? []) {
      if (!f.auto) initial[f.key] = (data as Record<string, unknown>)[f.key] ?? "";
    }
    setValues(initial);

    if (config.table === "findings") {
      const { data: sources } = await supabase
        .schema("investigation")
        .from("finding_sources")
        .select("is_contrary, facts(id, statement, fact_type, confidence)")
        .eq("finding_id", id);
      setFindingSources((sources as typeof findingSources | null) ?? []);
    }
    if (config.schema === "reporting" && config.table === "reports") {
      const { data: sections } = await supabase
        .schema("reporting")
        .from("report_sections")
        .select("id,section_number,heading,body,generation_source")
        .eq("report_id", id)
        .order("sort_order");
      setGeneratedRows((sections as Record<string, unknown>[] | null) ?? []);
    }
    if (config.schema === "court" && config.table === "appointments") {
      const { data: obligations } = await supabase
        .schema("court")
        .from("appointment_obligations")
        .select("id,clause_number,clause_category,clause_text,status,due_date")
        .eq("appointment_id", id)
        .order("clause_number");
      setGeneratedRows((obligations as Record<string, unknown>[] | null) ?? []);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [config, id]);

  useEffect(() => {
    load();
  }, [load]);

  function setField(key: string, value: unknown) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function handleUpdate(e: FormEvent) {
    e.preventDefault();
    const supabase = createClient();
    const payload: Record<string, unknown> = {};
    for (const f of config.updateFields ?? []) {
      if (f.auto === "current_user_id") {
        const {
          data: { user },
        } = await supabase.auth.getUser();
        payload[f.key] = user?.id;
        continue;
      }
      if (f.auto === "now") {
        payload[f.key] = new Date().toISOString();
        continue;
      }
      const v = values[f.key];
      if (v === undefined || v === "") continue;
      payload[f.key] = v;
    }

    setSubmitting(true);
    const { error } = await supabase
      .schema(config.schema)
      .from(config.table)
      .update(payload)
      .eq("id", id);
    setSubmitting(false);
    if (error) {
      addToast({ variant: "danger", message: error.message });
      return;
    }
    addToast({ variant: "success", message: `${config.label} updated.` });
    load();
  }

  async function handleLinkFact() {
    if (!linkFactId) return;
    const supabase = createClient();
    const { error } = await supabase.schema("investigation").from("finding_sources").insert({
      tenant_id: row?.tenant_id,
      matter_id: row?.matter_id,
      finding_id: id,
      fact_id: linkFactId,
      is_contrary: linkContrary,
    });
    if (error) {
      addToast({ variant: "danger", message: error.message });
      return;
    }
    setLinkFactId("");
    setLinkContrary(false);
    load();
  }

  async function handleSpecialAction() {
    const supabase = createClient();
    setActionLoading(true);
    const result =
      config.schema === "reporting"
        ? await supabase.schema("reporting").rpc("assemble_report", { p_report_id: id })
        : await supabase.schema("court").rpc("parse_appointment_order", { p_appointment_id: id });
    setActionLoading(false);
    if (result.error) return addToast({ variant: "danger", message: result.error.message });
    addToast({ variant: "success", message: `${result.data ?? 0} structured records generated.` });
    load();
  }

  if (loading) return <Text onBackground="neutral-weak">Loading…</Text>;
  if (error) return <Text onBackground="danger-weak">{error}</Text>;
  if (!row) return <Text onBackground="neutral-weak">Not found.</Text>;

  const editableKeys = new Set((config.updateFields ?? []).map((f) => f.key));
  const summaryEntries = Object.entries(row).filter(([k]) => !editableKeys.has(k));

  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">{config.label}</Heading>
        <Text onBackground="neutral-weak">{String(row.id)}</Text>
      </Column>

      <Column fillWidth gap="8">
        {summaryEntries.map(([key, value]) => (
          <Row key={key} fillWidth horizontal="between" gap="16">
            <Text onBackground="neutral-weak">{key}</Text>
            <Text style={{ textAlign: "right", wordBreak: "break-word" }}>
              {formatValue(value)}
            </Text>
          </Row>
        ))}
      </Column>

      {config.updateFields && config.updateFields.length > 0 && (
        <>
          <Line />
          <Column as="form" onSubmit={handleUpdate} gap="16" fillWidth>
            <Heading variant="heading-strong-s">Update</Heading>
            {config.updateFields
              .filter((f) => !f.auto)
              .map((f) => {
                switch (f.type) {
                  case "textarea":
                    return (
                      <Textarea
                        key={f.key}
                        id={f.key}
                        label={f.label}
                        description={f.help}
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
                        value={values[f.key] as number}
                        onChange={(v) => setField(f.key, v)}
                      />
                    );
                  case "select":
                    return (
                      <Select
                        key={f.key}
                        id={f.key}
                        label={f.label}
                        options={f.options ?? []}
                        value={values[f.key] as string}
                        onSelect={(v) => setField(f.key, v as string)}
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
                  case "relation":
                    if (!f.relation) return null;
                    return (
                      <RelationSelect
                        key={f.key}
                        id={f.key}
                        label={f.label}
                        relation={f.relation}
                        value={values[f.key] as string}
                        onSelect={(v) => setField(f.key, v)}
                      />
                    );
                  default:
                    return (
                      <Input
                        key={f.key}
                        id={f.key}
                        label={f.label}
                        description={f.help}
                        value={(values[f.key] as string) ?? ""}
                        onChange={(e) => setField(f.key, e.target.value)}
                      />
                    );
                }
              })}
            <Row horizontal="end">
              <Button type="submit" loading={submitting} data-border="sharp">
                Save
              </Button>
            </Row>
          </Column>
        </>
      )}

      {config.table === "findings" && (
        <>
          <Line />
          <Column gap="16" fillWidth>
            <Heading variant="heading-strong-s">Linked facts</Heading>
            <Text onBackground="neutral-weak">
              A finding can&apos;t be marked &quot;supported&quot; or &quot;final&quot; without at
              least one linked fact — the database enforces this, not just the form.
            </Text>
            {findingSources.length === 0 && (
              <Text onBackground="neutral-weak">No facts linked yet.</Text>
            )}
            {findingSources.map((s) => (
              <Row
                key={s.facts?.[0]?.id ?? `unavailable-${s.is_contrary}`}
                fillWidth
                horizontal="between"
                gap="16"
              >
                <Text>{s.facts?.[0]?.statement ?? "Linked fact unavailable"}</Text>
                <Text onBackground="neutral-weak">{s.is_contrary ? "contrary" : "supporting"}</Text>
              </Row>
            ))}
            <Row gap="8" vertical="end" wrap>
              <RelationSelect
                id="link-fact"
                label="Link a fact"
                relation={{
                  schema: "investigation",
                  table: "facts",
                  labelKey: "statement",
                  valueKey: "id",
                  matterScoped: true,
                }}
                value={linkFactId}
                onSelect={setLinkFactId}
              />
              <Checkbox
                id="link-contrary"
                label="Contrary evidence"
                isChecked={linkContrary}
                onToggle={() => setLinkContrary((c) => !c)}
              />
              <Button variant="secondary" onClick={handleLinkFact} disabled={!linkFactId}>
                Link
              </Button>
            </Row>
          </Column>
        </>
      )}

      {((config.schema === "reporting" && config.table === "reports") ||
        (config.schema === "court" && config.table === "appointments")) && (
        <>
          <Line />
          <Column gap="16" fillWidth>
            <Row fillWidth horizontal="between" vertical="center" wrap gap="12">
              <Column gap="4">
                <Heading variant="heading-strong-s">
                  {config.schema === "reporting"
                    ? "Generated report draft"
                    : "Parsed appointment obligations"}
                </Heading>
                <Text onBackground="neutral-weak">
                  {config.schema === "reporting"
                    ? "Assemble a repeatable working draft from matter scope, evidence, findings, and completed calculations."
                    : "Convert each substantive order line into a categorized, trackable obligation."}
                </Text>
              </Column>
              <Button onClick={handleSpecialAction} loading={actionLoading}>
                {config.schema === "reporting" ? "Assemble report" : "Parse order"}
              </Button>
            </Row>
            {generatedRows.length === 0 && (
              <Text onBackground="neutral-weak">Nothing generated yet.</Text>
            )}
            {generatedRows.map((item) => (
              <Column key={String(item.id)} gap="4" paddingY="8">
                <Text>
                  {config.schema === "reporting"
                    ? `${item.section_number ?? ""} ${item.heading ?? ""}`
                    : `${item.clause_number ?? ""} · ${item.clause_category ?? "duty"}`}
                </Text>
                <Text onBackground="neutral-weak">
                  {String(
                    config.schema === "reporting" ? (item.body ?? "") : (item.clause_text ?? ""),
                  )}
                </Text>
              </Column>
            ))}
          </Column>
        </>
      )}
    </Column>
  );
}
