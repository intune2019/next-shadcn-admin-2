"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import { Button, Card, Column, Heading, Row, Table, Text } from "@once-ui-system/core";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

function Metric({
  label,
  value,
  danger = false,
}: { label: string; value: string | number; danger?: boolean }) {
  return (
    <Card
      padding="16"
      border={danger ? "danger-medium" : "neutral-alpha-medium"}
      direction="column"
      gap="4"
      style={{ minWidth: 155 }}
    >
      <Text variant="label-default-s" onBackground="neutral-weak">
        {label}
      </Text>
      <Heading variant="heading-strong-l">{value}</Heading>
    </Card>
  );
}

export function FraudDashboard() {
  const { matterId } = useTenant();
  const [metrics, setMetrics] = useState({
    allegations: 0,
    evidence: 0,
    openAlerts: 0,
    highAlerts: 0,
    findings: 0,
    workpapers: 0,
    interviews: 0,
    exposure: 0,
  });
  const [alerts, setAlerts] = useState<Record<string, unknown>[]>([]);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [a, e, o, h, f, w, i, c, recent] = await Promise.all([
      db
        .schema("investigation")
        .from("allegations")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("evidence")
        .from("evidence_items")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("investigation")
        .from("alerts")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .neq("review_status", "closed"),
      db
        .schema("investigation")
        .from("alerts")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .in("aggregate_severity", ["high", "critical"])
        .neq("review_status", "closed"),
      db
        .schema("investigation")
        .from("findings")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("investigation")
        .from("workpapers")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("investigation")
        .from("interviews")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("calculations")
        .from("calculation_runs")
        .select("output_total")
        .eq("matter_id", matterId)
        .in("status", ["completed", "reviewed", "approved"]),
      db
        .schema("investigation")
        .from("alerts")
        .select("id,alert_title,alert_type,aggregate_severity,review_status")
        .eq("matter_id", matterId)
        .neq("review_status", "closed")
        .order("created_at", { ascending: false })
        .limit(8),
    ]);
    setMetrics({
      allegations: a.count ?? 0,
      evidence: e.count ?? 0,
      openAlerts: o.count ?? 0,
      highAlerts: h.count ?? 0,
      findings: f.count ?? 0,
      workpapers: w.count ?? 0,
      interviews: i.count ?? 0,
      exposure: (c.data ?? []).reduce((sum, row) => sum + Number(row.output_total ?? 0), 0),
    });
    setAlerts((recent.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  if (!matterId)
    return <Text onBackground="danger-weak">Choose a matter to open Fraud Examination.</Text>;
  return (
    <Column fillWidth gap="24">
      <Row horizontal="between" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">Fraud Examination</Heading>
          <Text onBackground="neutral-weak">
            Allegations, evidence, financial activity, investigative leads, workpapers, and
            supported findings.
          </Text>
        </Column>
        <Row gap="8">
          <Link href="/app/documents">
            <Button>New evidence</Button>
          </Link>
          <Link href="/app/rule-runner">
            <Button variant="secondary">Run analytics</Button>
          </Link>
        </Row>
      </Row>
      <Text variant="body-default-xs" onBackground="neutral-weak">
        Live matter-scoped records · refreshed when this dashboard opens
      </Text>
      <Row gap="12" wrap>
        <Metric label="Open alerts" value={metrics.openAlerts} danger={metrics.highAlerts > 0} />
        <Metric
          label="High / critical"
          value={metrics.highAlerts}
          danger={metrics.highAlerts > 0}
        />
        <Metric label="Potential exposure" value={`$${metrics.exposure.toLocaleString()}`} />
        <Metric label="Evidence" value={metrics.evidence} />
        <Metric label="Allegations" value={metrics.allegations} />
        <Metric label="Findings" value={metrics.findings} />
        <Metric label="Workpapers" value={metrics.workpapers} />
        <Metric label="Interviews" value={metrics.interviews} />
      </Row>
      <Heading variant="heading-strong-s">Priority alert review</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "severity", content: "Severity" },
            { key: "alert", content: "Alert" },
            { key: "type", content: "Type" },
            { key: "status", content: "Status" },
          ],
          rows: alerts.map((x) => [
            String(x.aggregate_severity),
            String(x.alert_title),
            String(x.alert_type),
            String(x.review_status),
          ]),
        }}
        emptyState={
          <Column gap="8" horizontal="center" padding="24">
            <Text onBackground="neutral-weak">No alerts are awaiting review.</Text>
            <Link href="/app/rule-runner">
              <Button size="s" variant="secondary">
                Run an approved fraud analytics pack
              </Button>
            </Link>
          </Column>
        }
      />
    </Column>
  );
}

export function SpecialServicesDashboard() {
  const { matterId } = useTenant();
  const [metrics, setMetrics] = useState({
    appointments: 0,
    obligations: 0,
    overdue: 0,
    claims: 0,
    pendingClaims: 0,
    assets: 0,
    assetValue: 0,
    fees: 0,
    reports: 0,
  });
  const [obligations, setObligations] = useState<Record<string, unknown>[]>([]);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [a, o, od, c, pc, assets, fees, reports, next] = await Promise.all([
      db
        .schema("court")
        .from("appointments")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("court")
        .from("appointment_obligations")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .neq("status", "completed"),
      db
        .schema("court")
        .from("appointment_obligations")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .neq("status", "completed")
        .lt("due_date", new Date().toISOString().slice(0, 10)),
      db
        .schema("claims")
        .from("claims")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId),
      db
        .schema("claims")
        .from("claims")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .not("review_status", "in", "(closed,approved)"),
      db.schema("court").from("assets").select("estimated_value").eq("matter_id", matterId),
      db
        .schema("court")
        .from("fees_expenses")
        .select("amount")
        .eq("matter_id", matterId)
        .in("status", ["submitted", "reviewed", "approved"]),
      db
        .schema("reporting")
        .from("reports")
        .select("id", { count: "exact", head: true })
        .eq("matter_id", matterId)
        .in("report_type", ["monitor_report", "receivership_report", "court_exhibits"]),
      db
        .schema("court")
        .from("appointment_obligations")
        .select("id,clause_category,clause_text,due_date,status")
        .eq("matter_id", matterId)
        .neq("status", "completed")
        .order("due_date")
        .limit(8),
    ]);
    const assetRows = assets.data ?? [];
    setMetrics({
      appointments: a.count ?? 0,
      obligations: o.count ?? 0,
      overdue: od.count ?? 0,
      claims: c.count ?? 0,
      pendingClaims: pc.count ?? 0,
      assets: assetRows.length,
      assetValue: assetRows.reduce((sum, row) => sum + Number(row.estimated_value ?? 0), 0),
      fees: (fees.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0),
      reports: reports.count ?? 0,
    });
    setObligations((next.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  if (!matterId)
    return <Text onBackground="danger-weak">Choose a matter to open Special Services.</Text>;
  return (
    <Column fillWidth gap="24">
      <Row horizontal="between" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">Special Services</Heading>
          <Text onBackground="neutral-weak">
            Court, monitor, receiver, special master, claims administration, assets, fees, and
            required deliverables.
          </Text>
        </Column>
        <Row gap="8">
          <Link href="/app/court-operations">
            <Button>Record activity</Button>
          </Link>
          <Link href="/app/report-workspace">
            <Button variant="secondary">Prepare report</Button>
          </Link>
        </Row>
      </Row>
      <Text variant="body-default-xs" onBackground="neutral-weak">
        Live matter-scoped court and claims records
      </Text>
      <Row gap="12" wrap>
        <Metric label="Open obligations" value={metrics.obligations} danger={metrics.overdue > 0} />
        <Metric label="Overdue" value={metrics.overdue} danger={metrics.overdue > 0} />
        <Metric label="Claims" value={metrics.claims} />
        <Metric label="Claims pending" value={metrics.pendingClaims} />
        <Metric label="Assets" value={metrics.assets} />
        <Metric label="Asset value" value={`$${metrics.assetValue.toLocaleString()}`} />
        <Metric label="Fees under review" value={`$${metrics.fees.toLocaleString()}`} />
        <Metric label="Court reports" value={metrics.reports} />
      </Row>
      <Heading variant="heading-strong-s">Next obligations</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "due", content: "Due" },
            { key: "category", content: "Category" },
            { key: "requirement", content: "Requirement" },
            { key: "status", content: "Status" },
          ],
          rows: obligations.map((x) => [
            String(x.due_date ?? "No date"),
            String(x.clause_category),
            String(x.clause_text),
            String(x.status),
          ]),
        }}
        emptyState={
          <Text onBackground="neutral-weak">No open court or appointment obligations.</Text>
        }
      />
    </Column>
  );
}
