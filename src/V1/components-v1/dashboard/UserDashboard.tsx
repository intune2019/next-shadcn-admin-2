"use client";

import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Column, Heading, Row, Table, Text } from "@once-ui-system/core";
import Link from "next/link";
import { useEffect, useState } from "react";

interface Matter {
  id: string;
  matter_number: string;
  matter_name: string;
  matter_type: string;
  status: string;
}
interface PortfolioMetrics {
  matters: number;
  active: number;
  alerts: number;
  highAlerts: number;
  evidence: number;
  exposure: number;
  overdue: number;
  draftReports: number;
  openTasks: number;
}
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
      style={{ minWidth: 150, flex: "0 0 150px" }}
    >
      <Text variant="label-default-s" onBackground="neutral-weak">
        {label}
      </Text>
      <Heading variant="heading-strong-l">{value}</Heading>
    </Card>
  );
}

export function UserDashboard() {
  const [displayName, setDisplayName] = useState("");
  const [matters, setMatters] = useState<Matter[]>([]);
  const [metrics, setMetrics] = useState<PortfolioMetrics>({
    matters: 0,
    active: 0,
    alerts: 0,
    highAlerts: 0,
    evidence: 0,
    exposure: 0,
    overdue: 0,
    draftReports: 0,
    openTasks: 0,
  });
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    async function load() {
      const db = createClient();
      const {
        data: { user },
      } = await db.auth.getUser();
      if (user) {
        const { data: profile } = await db
          .schema("core")
          .from("profiles")
          .select("display_name")
          .eq("id", user.id)
          .maybeSingle();
        setDisplayName(profile?.display_name || user.email || "");
      }
      const [m, a, h, e, c, d, r, t] = await Promise.all([
        db
          .schema("core")
          .from("matters")
          .select("id,matter_number,matter_name,matter_type,status")
          .order("updated_at", { ascending: false }),
        db
          .schema("investigation")
          .from("alerts")
          .select("id", { count: "exact", head: true })
          .neq("review_status", "closed"),
        db
          .schema("investigation")
          .from("alerts")
          .select("id", { count: "exact", head: true })
          .in("aggregate_severity", ["high", "critical"])
          .neq("review_status", "closed"),
        db.schema("evidence").from("evidence_items").select("id", { count: "exact", head: true }),
        db
          .schema("calculations")
          .from("calculation_runs")
          .select("output_total")
          .in("status", ["completed", "reviewed", "approved"]),
        db
          .schema("core")
          .from("deadlines")
          .select("id", { count: "exact", head: true })
          .eq("completed", false)
          .lt("due_at", new Date().toISOString()),
        db
          .schema("reporting")
          .from("reports")
          .select("id", { count: "exact", head: true })
          .not("status", "in", "(issued,superseded)"),
        db
          .schema("workflow")
          .from("tasks")
          .select("id", { count: "exact", head: true })
          .not("status", "in", "(completed,cancelled)"),
      ]);
      const list = (m.data as Matter[] | null) ?? [];
      setMatters(list);
      setMetrics({
        matters: list.length,
        active: list.filter((x) => x.status === "active").length,
        alerts: a.count ?? 0,
        highAlerts: h.count ?? 0,
        evidence: e.count ?? 0,
        exposure: (c.data ?? []).reduce((sum, row) => sum + Number(row.output_total ?? 0), 0),
        overdue: d.count ?? 0,
        draftReports: r.count ?? 0,
        openTasks: t.count ?? 0,
      });
      setLoading(false);
    }
    load();
  }, []);
  return (
    <Column fillWidth gap="24">
      <Row horizontal="between" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">
            Welcome{displayName ? `, ${displayName}` : ""}
          </Heading>
          <Text onBackground="neutral-weak">
            Your Forens_iQ portfolio—choose a matter to continue or select the work you want to
            perform.
          </Text>
        </Column>
        <Link href="/app/matters/new">
          <Button>New matter</Button>
        </Link>
      </Row>
      {loading ? (
        <Text onBackground="neutral-weak">Loading portfolio…</Text>
      ) : (
        <>
          <Heading variant="heading-strong-s">Global portfolio metrics</Heading>
          <Text variant="body-default-xs" onBackground="neutral-weak">
            Live totals across matters you are authorized to access
          </Text>
          <Row
            gap="12"
            wrap={false}
            style={{ overflowX: "auto", flexWrap: "nowrap", paddingBottom: "4px" }}
          >
            <Metric label="Accessible matters" value={metrics.matters} />
            <Metric label="Active matters" value={metrics.active} />
            <Metric label="Open alerts" value={metrics.alerts} danger={metrics.highAlerts > 0} />
            <Metric
              label="High / critical alerts"
              value={metrics.highAlerts}
              danger={metrics.highAlerts > 0}
            />
            <Metric label="Potential exposure" value={`$${metrics.exposure.toLocaleString()}`} />
            <Metric label="Evidence items" value={metrics.evidence} />
            <Metric
              label="Overdue deadlines"
              value={metrics.overdue}
              danger={metrics.overdue > 0}
            />
            <Metric label="Open tasks" value={metrics.openTasks} />
            <Metric label="Reports in progress" value={metrics.draftReports} />
          </Row>
          <Heading variant="heading-strong-s">What do you want to work on?</Heading>
          <Row gap="12" wrap>
            {[
              [
                "Fraud Examination",
                "Review allegations, evidence, alerts, funds flow, and findings.",
                "/app/fraud",
              ],
              [
                "Treasury",
                "Review cash, payments, reconciliations, access, and restricted funds.",
                "/app/treasury",
              ],
              ["GRC", "Work with risks, controls, testing, and remediation.", "/app/grc"],
              [
                "Special Services",
                "Manage court authority, obligations, receivership, claims, and reports.",
                "/app/special-services",
              ],
            ].map(([title, description, href]) => (
              <Link key={href} href={href} style={{ textDecoration: "none", flex: "1 1 220px" }}>
                <Card padding="20" border="neutral-alpha-medium" direction="column" gap="8">
                  <Heading variant="heading-strong-s">{title}</Heading>
                  <Text onBackground="neutral-weak">{description}</Text>
                  <Text variant="label-default-s" onBackground="brand-weak">
                    Open module →
                  </Text>
                </Card>
              </Link>
            ))}
          </Row>
          <Row horizontal="between" vertical="center">
            <Heading variant="heading-strong-s">Continue a matter</Heading>
            <Link href="/app/matters">
              <Button size="s" variant="secondary">
                View all matters
              </Button>
            </Link>
          </Row>
          <Table
            searchable
            striped
            data={{
              headers: [
                { key: "matter", content: "Matter" },
                { key: "number", content: "Number" },
                { key: "service", content: "Primary service" },
                { key: "status", content: "Status" },
                { key: "continue", content: "Continue" },
              ],
              rows: matters.map((m) => [
                m.matter_name,
                m.matter_number,
                m.matter_type,
                <Badge
                  key={m.id}
                  onBackground={m.status === "active" ? "success-strong" : "neutral-weak"}
                >
                  {m.status}
                </Badge>,
                <Link key={`open-${m.id}`} href={`/app/matters/${m.id}`}>
                  <Button size="s" variant="secondary">
                    Open
                  </Button>
                </Link>,
              ]),
            }}
            emptyState={
              <Column gap="8" horizontal="center" padding="24">
                <Text onBackground="neutral-weak">No matters are available yet.</Text>
                <Link href="/app/matters/new">
                  <Button size="s">Start a governed intake</Button>
                </Link>
              </Column>
            }
          />
        </>
      )}
    </Column>
  );
}
