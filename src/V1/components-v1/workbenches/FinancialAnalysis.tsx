"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Button,
  Column,
  Heading,
  Input,
  Line,
  Row,
  Select,
  Table,
  Text,
  useToast,
} from "@once-ui-system/core";
import { useCallback, useEffect, useMemo, useState } from "react";

interface Flow {
  leg_id: string;
  transaction_id: string;
  transaction_date: string | null;
  source_label: string;
  destination_label: string;
  amount: number;
  currency: string;
}
interface Account {
  id: string;
  institution_name: string | null;
  account_class: string | null;
}
interface SourceLeg {
  transaction_id: string;
  amount: number;
}
interface TraceRun {
  id: string;
  tracing_method: string;
  source_amount: number;
  traceable_amount: number | null;
  as_of_date: string;
  created_at: string;
}
interface Reconciliation {
  id: string;
  reconciliation_type: string;
  source_value: number | null;
  canonical_value: number | null;
  documented_adjustments: number | null;
  result: string;
  evaluated_at: string;
}

function FundsGraph({ flows }: { flows: Flow[] }) {
  const labels = useMemo(
    () =>
      Array.from(
        new Set(flows.flatMap((flow) => [flow.source_label, flow.destination_label])),
      ).slice(0, 14),
    [flows],
  );
  const positions = Object.fromEntries(
    labels.map((label, index) => {
      const angle = (Math.PI * 2 * index) / Math.max(labels.length, 1);
      return [label, { x: 400 + Math.cos(angle) * 270, y: 235 + Math.sin(angle) * 175 }];
    }),
  );
  if (!flows.length)
    return <Text onBackground="neutral-weak">No transaction legs are available for a graph.</Text>;
  return (
    <svg
      role="img"
      aria-label="Funds flow graph"
      viewBox="0 0 800 470"
      style={{ width: "100%", minHeight: 420, border: "1px solid var(--neutral-alpha-medium)" }}
    >
      <defs>
        <marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto">
          <path d="M0,0 L0,6 L9,3 z" fill="currentColor" />
        </marker>
      </defs>
      {flows.slice(0, 40).map((flow) => {
        const from = positions[flow.source_label];
        const to = positions[flow.destination_label];
        if (!from || !to) return null;
        return (
          <g key={flow.leg_id}>
            <line
              x1={from.x}
              y1={from.y}
              x2={to.x}
              y2={to.y}
              stroke="currentColor"
              opacity="0.35"
              markerEnd="url(#arrow)"
            />
            <text x={(from.x + to.x) / 2} y={(from.y + to.y) / 2} fontSize="10" fill="currentColor">
              {flow.currency} {flow.amount}
            </text>
          </g>
        );
      })}
      {labels.map((label) => {
        const point = positions[label];
        return (
          <g key={label}>
            <circle
              cx={point.x}
              cy={point.y}
              r="34"
              fill="var(--brand-alpha-medium)"
              stroke="currentColor"
            />
            <text
              x={point.x}
              y={point.y}
              textAnchor="middle"
              dominantBaseline="middle"
              fontSize="10"
              fill="currentColor"
            >
              {label.slice(0, 16)}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

export function FinancialAnalysis() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [flows, setFlows] = useState<Flow[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [sourceLegs, setSourceLegs] = useState<SourceLeg[]>([]);
  const [traces, setTraces] = useState<TraceRun[]>([]);
  const [reconciliations, setReconciliations] = useState<Reconciliation[]>([]);
  const [accountId, setAccountId] = useState("");
  const [sourceId, setSourceId] = useState("");
  const [method, setMethod] = useState("LIBR");
  const [opening, setOpening] = useState("0");
  const [asOf, setAsOf] = useState(new Date().toISOString().slice(0, 10));
  const [working, setWorking] = useState("");
  const [approvedAdjustments, setApprovedAdjustments] = useState("0");
  const load = useCallback(async () => {
    if (!matterId) return;
    const supabase = createClient();
    const [flowResult, accountResult, traceResult, reconResult] = await Promise.all([
      supabase
        .schema("analytics")
        .from("v_funds_flow")
        .select(
          "leg_id,transaction_id,transaction_date,source_label,destination_label,amount,currency",
        )
        .eq("matter_id", matterId)
        .order("transaction_date")
        .limit(100),
      supabase
        .schema("canonical")
        .from("bank_accounts")
        .select("id,institution_name,account_class")
        .eq("matter_id", matterId)
        .order("institution_name"),
      supabase
        .schema("calculations")
        .from("funds_trace_runs")
        .select("id,tracing_method,source_amount,traceable_amount,as_of_date,created_at")
        .eq("matter_id", matterId)
        .order("created_at", { ascending: false })
        .limit(20),
      supabase
        .schema("quality")
        .from("reconciliations")
        .select(
          "id,reconciliation_type,source_value,canonical_value,documented_adjustments,result,evaluated_at",
        )
        .eq("matter_id", matterId)
        .order("evaluated_at", { ascending: false })
        .limit(20),
    ]);
    setFlows((flowResult.data as Flow[] | null) ?? []);
    setAccounts((accountResult.data as Account[] | null) ?? []);
    setTraces((traceResult.data as TraceRun[] | null) ?? []);
    setReconciliations((reconResult.data as Reconciliation[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (!accountId || !matterId) {
      setSourceLegs([]);
      return;
    }
    createClient()
      .schema("canonical")
      .from("transaction_legs")
      .select("transaction_id,amount")
      .eq("matter_id", matterId)
      .eq("to_account_id", accountId)
      .then(({ data }) => setSourceLegs((data as SourceLeg[] | null) ?? []));
  }, [accountId, matterId]);
  async function trace() {
    if (!matterId || !accountId || !sourceId) return;
    setWorking("trace");
    const { data, error } = await createClient()
      .schema("calculations")
      .rpc("execute_funds_trace", {
        p_matter_id: matterId,
        p_account_id: accountId,
        p_source_transaction_id: sourceId,
        p_method: method,
        p_opening_balance: Number(opening) || 0,
        p_as_of_date: asOf,
      });
    setWorking("");
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Trace ${data} completed.` });
    load();
  }
  async function reconcile() {
    if (!matterId) return;
    setWorking("reconcile");
    const { data, error } = await createClient()
      .schema("quality")
      .rpc("run_invoice_payment_reconciliation", {
        p_matter_id: matterId,
        p_tolerance: 0.01,
        p_approved_adjustments: Number(approvedAdjustments) || 0,
      });
    setWorking("");
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Reconciliation ${data} completed.` });
    load();
  }
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Funds flow and reconciliation</Heading>
        <Text onBackground="neutral-weak">
          Transaction-leg graph, LIBR/FIFO/LIFO/netting traces, and stored invoice-to-payment
          reconciliation exceptions.
        </Text>
      </Column>
      {!matterId ? (
        <Text onBackground="danger-weak">Set an active matter first.</Text>
      ) : (
        <>
          <FundsGraph flows={flows} />
          <Line />
          <Heading variant="heading-strong-s">Run a commingled-funds trace</Heading>
          <Row gap="12" wrap vertical="end">
            <Select
              id="trace-account"
              label="Account"
              value={accountId}
              onSelect={(value) => {
                setAccountId(value as string);
                setSourceId("");
              }}
              options={accounts.map((account) => ({
                value: account.id,
                label: `${account.institution_name ?? account.id} · ${account.account_class ?? "account"}`,
              }))}
            />
            <Select
              id="trace-source"
              label="Identified source inflow"
              value={sourceId}
              onSelect={(value) => setSourceId(value as string)}
              options={sourceLegs.map((leg) => ({
                value: leg.transaction_id,
                label: `${leg.transaction_id} · ${leg.amount}`,
              }))}
            />
            <Select
              id="trace-method"
              label="Method"
              value={method}
              onSelect={(value) => setMethod(value as string)}
              options={["LIBR", "FIFO", "LIFO", "NETTING"].map((value) => ({
                value,
                label: value,
              }))}
            />
            <Input
              id="opening-balance"
              label="Opening untainted balance"
              value={opening}
              onChange={(event) => setOpening(event.target.value)}
            />
            <Input
              id="trace-date"
              label="Trace through date"
              type="date"
              value={asOf}
              onChange={(event) => setAsOf(event.target.value)}
            />
            <Button onClick={trace} loading={working === "trace"} disabled={!sourceId}>
              Run trace
            </Button>
          </Row>
          <Table
            data={{
              headers: [
                { key: "method", content: "Method" },
                { key: "source", content: "Source" },
                { key: "remaining", content: "Traceable" },
                { key: "date", content: "As of" },
              ],
              rows: traces.map((item) => [
                item.tracing_method,
                String(item.source_amount),
                String(item.traceable_amount ?? 0),
                item.as_of_date,
              ]),
            }}
            emptyState={<Text onBackground="neutral-weak">No trace runs yet.</Text>}
          />
          <Line />
          <Row horizontal="between" vertical="center" wrap gap="12">
            <Column gap="4">
              <Heading variant="heading-strong-s">Invoice-to-payment reconciliation</Heading>
              <Text onBackground="neutral-weak">
                Open balance = invoices − applied payments − credit memos + approved adjustments.
              </Text>
            </Column>
            <Row gap="8" vertical="end">
              <Input
                id="approved-adjustments"
                label="Approved adjustments"
                value={approvedAdjustments}
                onChange={(event) => setApprovedAdjustments(event.target.value)}
              />
              <Button onClick={reconcile} loading={working === "reconcile"}>
                Run reconciliation
              </Button>
            </Row>
          </Row>
          <Table
            data={{
              headers: [
                { key: "type", content: "Type" },
                { key: "source", content: "Invoice/credit total" },
                { key: "canonical", content: "Applied total" },
                { key: "adjustments", content: "Adjustments" },
                { key: "result", content: "Result" },
              ],
              rows: reconciliations.map((item) => [
                item.reconciliation_type,
                String(item.source_value ?? 0),
                String(item.canonical_value ?? 0),
                String(item.documented_adjustments ?? 0),
                item.result,
              ]),
            }}
            emptyState={<Text onBackground="neutral-weak">No reconciliations yet.</Text>}
          />
        </>
      )}
    </Column>
  );
}
