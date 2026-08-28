"use client";

import type { ResourceConfig } from "@/lib/resources/types";
import { createClient } from "@/lib/supabase/client";
import { Button, Column, Dialog, Heading, Row, Table, Text } from "@once-ui-system/core";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { ResourceForm } from "./ResourceForm";

function formatCell(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

const EMPTY_GUIDANCE: Record<string, { message: string; action?: string; href?: string }> = {
  matters: {
    message:
      "No matters are available. Start a governed intake to establish authority, scope, and access.",
    action: "Create matter",
    href: "/app/matters/new",
  },
  allegations: {
    message:
      "No allegations have been recorded. Create an allegation to define the suspected conduct, subjects, period, and initial evidence needs.",
  },
  "evidence-items": {
    message:
      "No evidence has been added. Upload documents, connect a data source, or record a physical evidence item.",
    action: "Open evidence workspace",
    href: "/app/documents",
  },
  transactions: {
    message:
      "No financial activity is available. Import an approved bank, ERP, payroll, AP, or general-ledger dataset.",
    action: "Import data",
    href: "/app/data-ingestion",
  },
  entities: {
    message:
      "No people or entities have been identified. Add a subject, import source data, or extract entities from evidence.",
    action: "Open evidence",
    href: "/app/documents",
  },
  alerts: {
    message:
      "No alerts are awaiting review. Run an approved analytics pack against an approved dataset.",
    action: "Run analytics",
    href: "/app/rule-runner",
  },
  findings: {
    message:
      "No findings have been approved. Review alerts and workpapers, then elevate supported facts for independent approval.",
  },
  reports: {
    message:
      "No report has been started. Choose a practitioner template and assemble it from approved findings, evidence, and calculations.",
    action: "Create report",
    href: "/app/report-workspace",
  },
  "appointment-obligations": {
    message:
      "No court obligations are recorded. Extract an appointment order or add an authorized duty or deadline.",
  },
  claims: { message: "No claims have been submitted for this matter." },
  mappings: {
    message:
      "No mapping package is available. A data architect must create and approve a source-to-canonical mapping before ingestion.",
  },
};

export function ResourceList({ config }: { config: ResourceConfig }) {
  const router = useRouter();
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const selectKeys = Array.from(new Set(["id", ...config.listColumns.map((c) => c.key)]));
    let query = supabase
      .schema(config.schema)
      .from(config.table)
      .select(selectKeys.join(","))
      .limit(100);

    if (config.orderBy) {
      query = query.order(config.orderBy.column, {
        ascending: config.orderBy.ascending ?? false,
      });
    }

    const { data, error } = await query;
    setLoading(false);
    if (error) {
      setError(error.message);
      return;
    }
    setRows((data as unknown as Record<string, unknown>[]) ?? []);
  }, [config]);

  useEffect(() => {
    load();
  }, [load]);

  const headers = config.listColumns.map((c) => ({
    content: c.label,
    key: c.key,
    width: c.width,
  }));
  const dataRows = rows.map((row) => config.listColumns.map((c) => formatCell(row[c.key])));
  const isMatterList = config.schema === "core" && config.table === "matters";
  const empty = EMPTY_GUIDANCE[config.slug] ?? {
    message: `No ${config.pluralLabel.toLowerCase()} are available for the active matter.`,
  };

  return (
    <Column fillWidth gap="24">
      <Row fillWidth horizontal="between" vertical="center" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">{config.pluralLabel}</Heading>
          {config.description && <Text onBackground="neutral-weak">{config.description}</Text>}
        </Column>
        {!config.readOnly && isMatterList && (
          <Link href="/app/matters/new" style={{ textDecoration: "none" }}>
            <Button data-border="sharp">New {config.label}</Button>
          </Link>
        )}
        {!config.readOnly && !isMatterList && (
          <Button data-border="sharp" onClick={() => setFormOpen(true)}>
            New {config.label}
          </Button>
        )}
      </Row>
      {error && (
        <Text onBackground="danger-weak">
          {error}
          {error.toLowerCase().includes("schema must be") &&
            ` — expose the "${config.schema}" schema under Supabase Project Settings -> API -> Exposed schemas.`}
        </Text>
      )}
      <Table
        data={{ headers, rows: dataRows }}
        loading={loading}
        emptyState={
          <Column gap="12" horizontal="center" padding="24">
            <Text onBackground="neutral-weak" align="center">
              {empty.message}
            </Text>
            {empty.href && empty.action && (
              <Link href={empty.href} style={{ textDecoration: "none" }}>
                <Button size="s" variant="secondary">
                  {empty.action}
                </Button>
              </Link>
            )}
          </Column>
        }
        searchable
        striped
        hoverable
        onRowClick={(i) => {
          const id = rows[i]?.id;
          if (id) router.push(`/app/${config.slug}/${id}`);
        }}
      />
      {!config.readOnly && !isMatterList && (
        <Dialog isOpen={formOpen} onClose={() => setFormOpen(false)} title={`New ${config.label}`}>
          <ResourceForm
            config={config}
            onCreated={() => {
              setFormOpen(false);
              load();
            }}
          />
        </Dialog>
      )}
    </Column>
  );
}
