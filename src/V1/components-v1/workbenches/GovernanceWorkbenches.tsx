"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Badge,
  Button,
  Card,
  Column,
  Heading,
  Input,
  Row,
  Select,
  Table,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
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
      style={{ minWidth: 150 }}
    >
      <Text variant="label-default-s" onBackground="neutral-weak">
        {label}
      </Text>
      <Heading variant="heading-strong-l">{value}</Heading>
    </Card>
  );
}

export function TreasuryWorkbench() {
  const { matterId, tenantId } = useTenant();
  const { addToast } = useToast();
  const [dashboard, setDashboard] = useState<Record<string, number>>({});
  const [exceptions, setExceptions] = useState<Record<string, unknown>[]>([]);
  const [reconciliations, setReconciliations] = useState<Record<string, unknown>[]>([]);
  const [working, setWorking] = useState(false);
  const [recon, setRecon] = useState({
    period: "",
    bank: "",
    ledger: "",
    adjustments: "0",
    tolerance: "0",
  });
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [d, e, r] = await Promise.all([
      db
        .schema("analytics")
        .from("v_treasury_dashboard")
        .select("*")
        .eq("matter_id", matterId)
        .maybeSingle(),
      db
        .schema("treasury")
        .from("exceptions")
        .select("id,exception_type,severity,amount,disposition,explanation")
        .eq("matter_id", matterId)
        .order("created_at", { ascending: false })
        .limit(100),
      db
        .schema("treasury")
        .from("reconciliations")
        .select("id,period_end,bank_balance,ledger_balance,variance,result,status")
        .eq("matter_id", matterId)
        .order("period_end", { ascending: false })
        .limit(50),
    ]);
    setDashboard((d.data as Record<string, number> | null) ?? {});
    setExceptions((e.data as Record<string, unknown>[] | null) ?? []);
    setReconciliations((r.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function runReview() {
    if (!matterId) return;
    setWorking(true);
    const { data, error } = await createClient()
      .schema("treasury")
      .rpc("run_payment_review", { p_matter_id: matterId });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Payment review complete: ${JSON.stringify(data)}` });
    load();
  }
  async function saveRecon() {
    if (!matterId || !tenantId || !recon.period) return;
    setWorking(true);
    const { error } = await createClient()
      .schema("treasury")
      .from("reconciliations")
      .insert({
        tenant_id: tenantId,
        matter_id: matterId,
        period_end: recon.period,
        bank_balance: Number(recon.bank),
        ledger_balance: Number(recon.ledger),
        documented_adjustments: Number(recon.adjustments),
        tolerance: Number(recon.tolerance),
      });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: "Reconciliation calculated and preserved." });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Row horizontal="between" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">Treasury command center</Heading>
          <Text onBackground="neutral-weak">
            Cash governance, payment exceptions, reconciliation, restricted funds, and access
            review.
          </Text>
        </Column>
        <Button onClick={runReview} loading={working}>
          Run payment controls
        </Button>
      </Row>
      <Text variant="body-default-xs" onBackground="neutral-weak">
        Source: analytics.v_treasury_dashboard · matter-scoped live records
      </Text>
      <Row gap="12" wrap>
        <Metric
          label="Cash position"
          value={Number(dashboard.cash_position ?? 0).toLocaleString()}
        />
        <Metric label="Bank accounts" value={dashboard.bank_accounts ?? 0} />
        <Metric
          label="Open exceptions"
          value={dashboard.open_exceptions ?? 0}
          danger={Boolean(dashboard.open_exceptions)}
        />
        <Metric
          label="Unreconciled"
          value={dashboard.unreconciled_accounts ?? 0}
          danger={Boolean(dashboard.unreconciled_accounts)}
        />
        <Metric
          label="Access reviews"
          value={dashboard.access_reviews_due ?? 0}
          danger={Boolean(dashboard.access_reviews_due)}
        />
        <Metric
          label="Exception exposure"
          value={Number(dashboard.exception_exposure ?? 0).toLocaleString()}
        />
      </Row>
      <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
        <Heading variant="heading-strong-s">Prepare bank-to-ledger reconciliation</Heading>
        <Row gap="12" wrap>
          <Input
            id="recon-period"
            type="date"
            label="Period end"
            value={recon.period}
            onChange={(e) => setRecon({ ...recon, period: e.target.value })}
          />
          <Input
            id="bank-balance"
            label="Bank balance"
            value={recon.bank}
            onChange={(e) => setRecon({ ...recon, bank: e.target.value })}
          />
          <Input
            id="ledger-balance"
            label="Ledger balance"
            value={recon.ledger}
            onChange={(e) => setRecon({ ...recon, ledger: e.target.value })}
          />
          <Input
            id="adjustments"
            label="Documented adjustments"
            value={recon.adjustments}
            onChange={(e) => setRecon({ ...recon, adjustments: e.target.value })}
          />
          <Input
            id="tolerance"
            label="Tolerance"
            value={recon.tolerance}
            onChange={(e) => setRecon({ ...recon, tolerance: e.target.value })}
          />
          <Button onClick={saveRecon} disabled={!recon.period}>
            Calculate
          </Button>
        </Row>
      </Card>
      <Heading variant="heading-strong-s">Payment and control exceptions</Heading>
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "type", content: "Type" },
            { key: "severity", content: "Severity" },
            { key: "amount", content: "Amount" },
            { key: "status", content: "Disposition" },
            { key: "why", content: "Explanation" },
          ],
          rows: exceptions.map((x) => [
            String(x.exception_type),
            String(x.severity),
            String(x.amount ?? "—"),
            String(x.disposition),
            String(x.explanation),
          ]),
        }}
        emptyState={<Text onBackground="neutral-weak">No treasury exceptions.</Text>}
      />
      <Heading variant="heading-strong-s">Reconciliations</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "period", content: "Period" },
            { key: "bank", content: "Bank" },
            { key: "ledger", content: "Ledger" },
            { key: "variance", content: "Variance" },
            { key: "result", content: "Result" },
          ],
          rows: reconciliations.map((x) => [
            String(x.period_end),
            String(x.bank_balance),
            String(x.ledger_balance),
            String(x.variance),
            String(x.result),
          ]),
        }}
        emptyState={<Text onBackground="neutral-weak">No reconciliations prepared.</Text>}
      />
    </Column>
  );
}

export function GrcWorkbench() {
  const { matterId, tenantId } = useTenant();
  const { addToast } = useToast();
  const [dashboard, setDashboard] = useState<Record<string, number>>({});
  const [risks, setRisks] = useState<Record<string, unknown>[]>([]);
  const [controls, setControls] = useState<Record<string, unknown>[]>([]);
  const [tests, setTests] = useState<Record<string, unknown>[]>([]);
  const [actions, setActions] = useState<Record<string, unknown>[]>([]);
  const [risk, setRisk] = useState({ code: "", title: "", description: "" });
  const [control, setControl] = useState({ code: "", title: "", description: "" });
  const [testId, setTestId] = useState("");
  const [working, setWorking] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [d, r, c, t, a] = await Promise.all([
      db
        .schema("analytics")
        .from("v_grc_dashboard")
        .select("*")
        .eq("matter_id", matterId)
        .maybeSingle(),
      db
        .schema("grc")
        .from("risks")
        .select("id,risk_code,title,status,inherent_likelihood,inherent_impact")
        .eq("matter_id", matterId),
      db
        .schema("grc")
        .from("controls")
        .select("id,control_code,title,status,control_type")
        .eq("matter_id", matterId),
      db
        .schema("grc")
        .from("control_tests")
        .select(
          "id,control_id,result,status,exception_rate,monetary_exception_rate,residual_risk_score",
        )
        .eq("matter_id", matterId),
      db
        .schema("grc")
        .from("remediation_actions")
        .select("id,title,priority,status,due_at,owner_ref")
        .eq("matter_id", matterId)
        .order("due_at"),
    ]);
    setDashboard((d.data as Record<string, number> | null) ?? {});
    setRisks((r.data as Record<string, unknown>[] | null) ?? []);
    setControls((c.data as Record<string, unknown>[] | null) ?? []);
    setTests((t.data as Record<string, unknown>[] | null) ?? []);
    setActions((a.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function add(kind: "risk" | "control") {
    if (!matterId || !tenantId) return;
    setWorking(true);
    const db = createClient().schema("grc");
    const { error } =
      kind === "risk"
        ? await db.from("risks").insert({
            tenant_id: tenantId,
            matter_id: matterId,
            risk_code: risk.code,
            title: risk.title,
            description: risk.description,
          })
        : await db.from("controls").insert({
            tenant_id: tenantId,
            matter_id: matterId,
            control_code: control.code,
            title: control.title,
            description: control.description,
          });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `${kind} created.` });
    load();
  }
  async function finalize() {
    if (!testId) return;
    setWorking(true);
    const { data, error } = await createClient()
      .schema("grc")
      .rpc("finalize_control_test", { p_test_id: testId });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Test reviewed: ${JSON.stringify(data)}` });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">GRC and audit workspace</Heading>
        <Text onBackground="neutral-weak">
          Risks, controls, audit testing, exceptions, residual risk, and corrective actions.
        </Text>
      </Column>
      <Text variant="body-default-xs" onBackground="neutral-weak">
        Source: analytics.v_grc_dashboard · matter-scoped live records
      </Text>
      <Row gap="12" wrap>
        <Metric label="Open risks" value={dashboard.open_risks ?? 0} />
        <Metric label="Implemented controls" value={dashboard.implemented_controls ?? 0} />
        <Metric
          label="Failed tests"
          value={dashboard.failed_tests ?? 0}
          danger={Boolean(dashboard.failed_tests)}
        />
        <Metric
          label="Overdue actions"
          value={dashboard.overdue_actions ?? 0}
          danger={Boolean(dashboard.overdue_actions)}
        />
        <Metric
          label="Average residual risk"
          value={Number(dashboard.average_residual_risk ?? 0).toFixed(2)}
        />
      </Row>
      <Row gap="16" wrap>
        <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12" flex={1}>
          <Heading variant="heading-strong-s">Add risk</Heading>
          <Input
            id="risk-code"
            label="Risk code"
            value={risk.code}
            onChange={(e) => setRisk({ ...risk, code: e.target.value })}
          />
          <Input
            id="risk-title"
            label="Title"
            value={risk.title}
            onChange={(e) => setRisk({ ...risk, title: e.target.value })}
          />
          <Textarea
            id="risk-description"
            label="Description"
            value={risk.description}
            onChange={(e) => setRisk({ ...risk, description: e.target.value })}
          />
          <Button
            onClick={() => add("risk")}
            loading={working}
            disabled={!risk.code || !risk.title}
          >
            Create risk
          </Button>
        </Card>
        <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12" flex={1}>
          <Heading variant="heading-strong-s">Add control</Heading>
          <Input
            id="control-code"
            label="Control code"
            value={control.code}
            onChange={(e) => setControl({ ...control, code: e.target.value })}
          />
          <Input
            id="control-title"
            label="Title"
            value={control.title}
            onChange={(e) => setControl({ ...control, title: e.target.value })}
          />
          <Textarea
            id="control-description"
            label="Description"
            value={control.description}
            onChange={(e) => setControl({ ...control, description: e.target.value })}
          />
          <Button
            onClick={() => add("control")}
            loading={working}
            disabled={!control.code || !control.title}
          >
            Create control
          </Button>
        </Card>
      </Row>
      <Row gap="12" vertical="end">
        <Select
          id="test-review"
          label="Control test for independent review"
          value={testId}
          onSelect={(v) => setTestId(v as string)}
          options={tests.map((t) => ({
            value: String(t.id),
            label: `${String(t.result)} · ${String(t.id).slice(0, 8)}`,
          }))}
        />
        <Button onClick={finalize} loading={working} disabled={!testId}>
          Calculate and review test
        </Button>
      </Row>
      <Heading variant="heading-strong-s">Risk register</Heading>
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "code", content: "Code" },
            { key: "title", content: "Risk" },
            { key: "likelihood", content: "Likelihood" },
            { key: "impact", content: "Impact" },
            { key: "status", content: "Status" },
          ],
          rows: risks.map((r) => [
            String(r.risk_code),
            String(r.title),
            String(r.inherent_likelihood),
            String(r.inherent_impact),
            String(r.status),
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Control matrix</Heading>
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "code", content: "Code" },
            { key: "title", content: "Control" },
            { key: "type", content: "Type" },
            { key: "status", content: "Status" },
          ],
          rows: controls.map((c) => [
            String(c.control_code),
            String(c.title),
            String(c.control_type),
            String(c.status),
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Corrective actions</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "action", content: "Action" },
            { key: "priority", content: "Priority" },
            { key: "owner", content: "Owner" },
            { key: "due", content: "Due" },
            { key: "status", content: "Status" },
          ],
          rows: actions.map((a) => [
            String(a.title),
            String(a.priority),
            String(a.owner_ref ?? "—"),
            String(a.due_at),
            String(a.status),
          ]),
        }}
      />
    </Column>
  );
}
