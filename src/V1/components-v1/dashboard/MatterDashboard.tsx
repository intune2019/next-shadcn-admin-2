"use client";

import { groupCount } from "@/lib/dashboard/aggregate";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Badge,
  BarChart,
  Button,
  Card,
  Column,
  Heading,
  Line,
  LineChart,
  Row,
  Text,
} from "@once-ui-system/core";
import Link from "next/link";
import { useEffect, useState } from "react";

function groupByWeek(rows: { created_at: string }[]): { label: string; count: number }[] {
  const counts = new Map<number, number>();
  for (const row of rows) {
    const d = new Date(row.created_at);
    const weekStart = new Date(d);
    weekStart.setDate(d.getDate() - d.getDay());
    weekStart.setHours(0, 0, 0, 0);
    const key = weekStart.getTime();
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return Array.from(counts.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([ts, count]) => ({
      label: new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      count,
    }));
}

interface Matter {
  id: string;
  matter_number: string;
  matter_name: string;
  matter_type: string;
  status: string;
  confidentiality: string;
}

interface Counts {
  evidence: number;
  facts: number;
  findings: number;
  allegations: number;
  openAlerts: number;
  documents: number;
}

interface Readiness {
  has_authority: boolean;
  scope_approved: boolean;
  enabled_modules: number;
  datasets: number;
  approved_datasets: number;
  open_data_exceptions: number;
  open_alerts: number;
  overdue_deadlines: number;
  calculations_awaiting_review: number;
  draft_reports: number;
}

const TILES: { key: keyof Counts; label: string; href: string }[] = [
  { key: "evidence", label: "Preserved evidence", href: "/app/documents" },
  { key: "facts", label: "Verified facts", href: "/app/facts" },
  { key: "findings", label: "Approved findings", href: "/app/findings" },
  { key: "allegations", label: "Allegations", href: "/app/allegations" },
  { key: "openAlerts", label: "Open alerts", href: "/app/alerts" },
  { key: "documents", label: "Searchable documents", href: "/app/documents" },
];

export function MatterDashboard({ matterId }: { matterId: string }) {
  const { setMatterId, setTenantId } = useTenant();
  const [matter, setMatter] = useState<Matter | null>(null);
  const [counts, setCounts] = useState<Counts | null>(null);
  const [loading, setLoading] = useState(true);
  const [findingsByStatus, setFindingsByStatus] = useState<{ label: string; count: number }[]>([]);
  const [evidenceByType, setEvidenceByType] = useState<{ label: string; count: number }[]>([]);
  const [activity, setActivity] = useState<{ label: string; count: number }[]>([]);
  const [readiness, setReadiness] = useState<Readiness | null>(null);
  const [exposure, setExposure] = useState(0);
  const [openActions, setOpenActions] = useState(0);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setLoading(true);
      const supabase = createClient();
      const { data: m } = await supabase
        .schema("core")
        .from("matters")
        .select("id, matter_number, matter_name, matter_type, status, confidentiality, tenant_id")
        .eq("id", matterId)
        .single();
      if (cancelled) return;
      if (m) {
        setMatter(m as Matter);
        setMatterId(m.id);
        setTenantId((m as unknown as { tenant_id: string }).tenant_id);
      }

      const { data: readinessRow } = await supabase
        .schema("analytics")
        .from("v_matter_readiness")
        .select(
          "has_authority,scope_approved,enabled_modules,datasets,approved_datasets,open_data_exceptions,open_alerts,overdue_deadlines,calculations_awaiting_review,draft_reports",
        )
        .eq("matter_id", matterId)
        .maybeSingle();
      if (cancelled) return;
      setReadiness((readinessRow as Readiness | null) ?? null);
      const [calculationTotals, remediation] = await Promise.all([
        supabase
          .schema("calculations")
          .from("calculation_runs")
          .select("output_total")
          .eq("matter_id", matterId)
          .in("status", ["completed", "reviewed", "approved"]),
        supabase
          .schema("grc")
          .from("remediation_actions")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId)
          .not("status", "in", "(closed,validated)"),
      ]);
      setExposure(
        (calculationTotals.data ?? []).reduce((sum, row) => sum + Number(row.output_total ?? 0), 0),
      );
      setOpenActions(remediation.count ?? 0);

      const [evidence, facts, findings, allegations, openAlerts, documents] = await Promise.all([
        supabase
          .schema("evidence")
          .from("evidence_items")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId),
        supabase
          .schema("investigation")
          .from("facts")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId),
        supabase
          .schema("investigation")
          .from("findings")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId),
        supabase
          .schema("investigation")
          .from("allegations")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId),
        supabase
          .schema("investigation")
          .from("alerts")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId)
          .neq("review_status", "closed"),
        supabase
          .schema("evidence")
          .from("evidence_files")
          .select("id", { count: "exact", head: true })
          .eq("matter_id", matterId),
      ]);
      if (cancelled) return;
      setCounts({
        evidence: evidence.count ?? 0,
        facts: facts.count ?? 0,
        findings: findings.count ?? 0,
        allegations: allegations.count ?? 0,
        openAlerts: openAlerts.count ?? 0,
        documents: documents.count ?? 0,
      });

      const [findingsRows, evidenceRows, activityRows] = await Promise.all([
        supabase
          .schema("investigation")
          .from("findings")
          .select("conclusion_status")
          .eq("matter_id", matterId),
        supabase
          .schema("evidence")
          .from("evidence_items")
          .select("evidence_type")
          .eq("matter_id", matterId),
        supabase
          .schema("evidence")
          .from("evidence_items")
          .select("created_at")
          .eq("matter_id", matterId),
      ]);
      if (cancelled) return;
      setFindingsByStatus(
        groupCount((findingsRows.data ?? []).map((r) => ({ key: r.conclusion_status }))),
      );
      setEvidenceByType(
        groupCount((evidenceRows.data ?? []).map((r) => ({ key: r.evidence_type }))),
      );
      setActivity(groupByWeek(activityRows.data ?? []));
      setLoading(false);
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [matterId, setMatterId, setTenantId]);

  if (loading) return <Text onBackground="neutral-weak">Loading…</Text>;
  if (!matter) return <Text onBackground="danger-weak">Matter not found or no access.</Text>;

  return (
    <Column fillWidth gap="24">
      <Column gap="8">
        <Row gap="8" vertical="center" wrap>
          <Badge
            textVariant="code-default-s"
            border="neutral-alpha-medium"
            onBackground="neutral-medium"
          >
            {matter.matter_number}
          </Badge>
          <Badge
            textVariant="code-default-s"
            border="neutral-alpha-medium"
            onBackground="neutral-medium"
          >
            {matter.status}
          </Badge>
        </Row>
        <Heading variant="heading-strong-l">{matter.matter_name}</Heading>
        <Text onBackground="neutral-weak">
          {matter.matter_type} · {matter.confidentiality}
        </Text>
      </Column>

      <Row gap="8" wrap>
        <Link href="/app/documents" style={{ textDecoration: "none" }}>
          <Button>New evidence</Button>
        </Link>
        <Link href="/app/data-ingestion" style={{ textDecoration: "none" }}>
          <Button variant="secondary">Import data</Button>
        </Link>
        <Link href="/app/rule-runner" style={{ textDecoration: "none" }}>
          <Button variant="secondary">Run analytics</Button>
        </Link>
        <Link href="/app/calculations" style={{ textDecoration: "none" }}>
          <Button variant="secondary">Start calculation</Button>
        </Link>
        <Link href="/app/report-workspace" style={{ textDecoration: "none" }}>
          <Button variant="secondary">Draft report</Button>
        </Link>
      </Row>

      <Row gap="12" wrap>
        <Card padding="16" border="neutral-alpha-medium" direction="column" gap="4">
          <Text variant="label-default-s" onBackground="neutral-weak">
            Potential exposure
          </Text>
          <Heading variant="heading-strong-l">${exposure.toLocaleString()}</Heading>
        </Card>
        <Card padding="16" border="neutral-alpha-medium" direction="column" gap="4">
          <Text variant="label-default-s" onBackground="neutral-weak">
            Open remediation
          </Text>
          <Heading variant="heading-strong-l">{openActions}</Heading>
        </Card>
        <Card padding="16" border="neutral-alpha-medium" direction="column" gap="4">
          <Text variant="label-default-s" onBackground="neutral-weak">
            Reports due / draft
          </Text>
          <Heading variant="heading-strong-l">{readiness?.draft_reports ?? 0}</Heading>
        </Card>
      </Row>

      <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
        <Heading variant="heading-strong-s">Priority actions</Heading>
        {!readiness?.scope_approved && (
          <Link href={`/app/matters/${matterId}/authority`}>
            Approve authority and investigation scope
          </Link>
        )}
        {(readiness?.open_data_exceptions ?? 0) > 0 && (
          <Link href="/app/data-ingestion">
            Resolve {readiness?.open_data_exceptions} data-readiness exceptions
          </Link>
        )}
        {(readiness?.open_alerts ?? 0) > 0 && (
          <Link href="/app/alerts">Review {readiness?.open_alerts} open alerts</Link>
        )}
        {(readiness?.calculations_awaiting_review ?? 0) > 0 && (
          <Link href="/app/calculations">
            Review {readiness?.calculations_awaiting_review} completed calculations
          </Link>
        )}
        {(readiness?.overdue_deadlines ?? 0) > 0 && (
          <Link href="/app/appointment-obligations">
            Address {readiness?.overdue_deadlines} overdue deadlines
          </Link>
        )}
        {readiness?.scope_approved &&
          !(
            readiness.open_data_exceptions ||
            readiness.open_alerts ||
            readiness.calculations_awaiting_review ||
            readiness.overdue_deadlines
          ) && (
            <Text onBackground="success-weak">
              No urgent review items. Continue investigation or begin report drafting.
            </Text>
          )}
      </Card>

      <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
        <Heading variant="heading-strong-s">Investigation progress</Heading>
        <Row gap="8" wrap>
          {[
            ["Intake", true],
            ["Preservation", (counts?.evidence ?? 0) > 0],
            ["Data readiness", (readiness?.approved_datasets ?? 0) > 0],
            ["Analysis", (counts?.openAlerts ?? 0) > 0 || exposure > 0],
            ["Findings", (counts?.findings ?? 0) > 0],
            ["Reporting", (readiness?.draft_reports ?? 0) > 0],
          ].map(([label, done]) => (
            <Badge key={String(label)} onBackground={done ? "success-strong" : "neutral-weak"}>
              {String(label)} · {done ? "Started" : "Pending"}
            </Badge>
          ))}
        </Row>
      </Card>

      <Card padding="20" radius="l" border="neutral-alpha-medium" direction="column" gap="16">
        <Row fillWidth horizontal="between" vertical="center" wrap gap="12">
          <Column gap="4">
            <Heading variant="heading-strong-s">Workflow readiness</Heading>
            <Text onBackground="neutral-weak" variant="body-default-s">
              Source: analytics.v_matter_readiness · live governed records for this matter
            </Text>
          </Column>
          <Link href={`/app/matters/${matterId}/authority`} style={{ textDecoration: "none" }}>
            <Button>
              {readiness?.scope_approved ? "Review approved scope" : "Complete authority review"}
            </Button>
          </Link>
        </Row>
        <Row gap="12" wrap>
          <Badge onBackground={readiness?.has_authority ? "success-strong" : "warning-strong"}>
            Authority {readiness?.has_authority ? "recorded" : "missing"}
          </Badge>
          <Badge onBackground={readiness?.scope_approved ? "success-strong" : "warning-strong"}>
            Scope {readiness?.scope_approved ? "approved" : "approval required"}
          </Badge>
          <Badge
            onBackground={
              (readiness?.approved_datasets ?? 0) > 0 ? "success-strong" : "neutral-weak"
            }
          >
            {readiness?.approved_datasets ?? 0}/{readiness?.datasets ?? 0} datasets approved
          </Badge>
          <Badge
            onBackground={
              (readiness?.overdue_deadlines ?? 0) > 0 ? "danger-strong" : "success-strong"
            }
          >
            {readiness?.overdue_deadlines ?? 0} overdue deadlines
          </Badge>
        </Row>
        <Row gap="16" wrap>
          {[
            ["Enabled modules", readiness?.enabled_modules ?? 0],
            ["Data exceptions", readiness?.open_data_exceptions ?? 0],
            ["Open alerts", readiness?.open_alerts ?? 0],
            ["Calculations to review", readiness?.calculations_awaiting_review ?? 0],
            ["Draft reports", readiness?.draft_reports ?? 0],
          ].map(([label, value]) => (
            <Column key={String(label)} gap="2" style={{ minWidth: 130 }}>
              <Text variant="label-default-s" onBackground="neutral-weak">
                {label}
              </Text>
              <Heading variant="heading-strong-m">{value}</Heading>
            </Column>
          ))}
        </Row>
      </Card>

      <Line />

      <Row fillWidth gap="16" wrap>
        {TILES.map((tile) => (
          <Link
            key={tile.key}
            href={tile.href}
            style={{ textDecoration: "none", flex: "1 1 160px" }}
          >
            <Card padding="20" radius="l" border="neutral-alpha-medium" direction="column" gap="8">
              <Text onBackground="neutral-weak" variant="label-default-s">
                {tile.label}
              </Text>
              <Heading variant="display-strong-s">{counts ? counts[tile.key] : "—"}</Heading>
            </Card>
          </Link>
        ))}
      </Row>

      <Line />

      <Row fillWidth gap="16" wrap>
        <BarChart
          flex={1}
          minWidth={20}
          title="Findings by status"
          series={{ key: "count" }}
          data={findingsByStatus}
          axis="x"
          grid="y"
          tooltip
          emptyState={<Text onBackground="neutral-weak">No findings yet.</Text>}
        />
        <BarChart
          flex={1}
          minWidth={20}
          title="Evidence by type"
          series={{ key: "count" }}
          data={evidenceByType}
          axis="x"
          grid="y"
          tooltip
          emptyState={<Text onBackground="neutral-weak">No evidence yet.</Text>}
        />
      </Row>

      <LineChart
        fillWidth
        title="Evidence intake over time"
        description="New evidence items collected per week"
        series={{ key: "count" }}
        data={activity}
        axis="x"
        grid="both"
        tooltip
        emptyState={<Text onBackground="neutral-weak">No evidence collected yet.</Text>}
      />
    </Column>
  );
}
