"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Button,
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
import { useCallback, useEffect, useMemo, useState } from "react";

interface Model {
  current_version_id: string | null;
  model_code: string;
  model_name: string;
}
interface Run {
  id: string;
  run_name: string | null;
  status: string;
  output_total: number | null;
  output_currency: string | null;
  narrative: string | null;
  created_at: string;
}
const templates: Record<string, object> = {
  FX_LOSS_KNOWN_UNAUTHORIZED_DISBURSEMENTS_V1: {
    currency: "USD",
    gross_loss: 100000,
    verified_recoveries: 10000,
    approved_offsets: 5000,
  },
  FX_LOSS_NET_V1: {
    currency: "USD",
    gross_loss: 100000,
    verified_recoveries: 10000,
    approved_offsets: 5000,
  },
  FX_RESTITUTION_CANDIDATE_V1: {
    currency: "USD",
    gross_actual_loss: 100000,
    returned_property_value: 5000,
    verified_recovery: 10000,
    approved_credit_or_offset: 0,
  },
  LIT_DMG_LOST_PROFITS_V1: {
    currency: "USD",
    but_for_revenue: 500000,
    actual_revenue: 300000,
    avoided_costs: 60000,
    incremental_adjustments: 0,
    incremental_mitigation_costs: 10000,
  },
  LIT_DMG_DISGORGEMENT_V1: {
    currency: "USD",
    wrongful_revenue: 300000,
    directly_attributable_costs: 80000,
    approved_offsets: 0,
  },
  ECON_PREJUDGMENT_INTEREST_V1: {
    currency: "USD",
    principal: 100000,
    annual_rate: 0.08,
    start_date: "2025-01-01",
    end_date: "2026-01-01",
    day_count_basis: 365,
    interest_method: "simple",
  },
  ECON_PRESENT_VALUE_V1: {
    currency: "USD",
    discount_rate: 0.08,
    cash_flows: [
      { period: 1, amount: 100000 },
      { period: 2, amount: 100000 },
    ],
  },
  TREASURY_BANK_RECONCILIATION_V1: {
    currency: "USD",
    bank_ending_balance: 100000,
    ledger_ending_balance: 95000,
    outstanding_checks: 10000,
    deposits_in_transit: 5000,
    approved_adjustments: 0,
  },
};

export function CalculationWorkbench() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [models, setModels] = useState<Model[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [versionId, setVersionId] = useState("");
  const [inputs, setInputs] = useState("{}");
  const [assumptions, setAssumptions] = useState("{}");
  const [name, setName] = useState("");
  const [running, setRunning] = useState(false);
  const selected = useMemo(
    () => models.find((model) => model.current_version_id === versionId),
    [models, versionId],
  );
  const load = useCallback(async () => {
    const supabase = createClient();
    const [{ data: modelData }, { data: runData }] = await Promise.all([
      supabase
        .schema("calculations")
        .from("model_definitions")
        .select("current_version_id,model_code,model_name")
        .eq("approval_status", "approved")
        .not("current_version_id", "is", null)
        .order("model_code"),
      matterId
        ? supabase
            .schema("calculations")
            .from("calculation_runs")
            .select("id,run_name,status,output_total,output_currency,narrative,created_at")
            .eq("matter_id", matterId)
            .order("created_at", { ascending: false })
            .limit(25)
        : Promise.resolve({ data: [] }),
    ]);
    setModels((modelData as Model[] | null) ?? []);
    setRuns((runData as Run[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  function choose(value: string) {
    setVersionId(value);
    const model = models.find((item) => item.current_version_id === value);
    setInputs(JSON.stringify(templates[model?.model_code ?? ""] ?? { currency: "USD" }, null, 2));
  }
  async function run() {
    if (!matterId || !versionId) return;
    let parsedInputs: object;
    let parsedAssumptions: object;
    try {
      parsedInputs = JSON.parse(inputs);
      parsedAssumptions = JSON.parse(assumptions);
    } catch {
      return addToast({ variant: "danger", message: "Inputs and assumptions must be valid JSON." });
    }
    setRunning(true);
    const { data, error } = await createClient()
      .schema("calculations")
      .rpc("execute_model", {
        p_model_version_id: versionId,
        p_matter_id: matterId,
        p_inputs: parsedInputs,
        p_assumptions: parsedAssumptions,
        p_run_name: name || null,
      });
    setRunning(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Calculation ${data} completed and hashed.` });
    load();
  }
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Calculation engine</Heading>
        <Text onBackground="neutral-weak">
          Governed known-loss, restitution, lost-profit, disgorgement, interest, present-value, and
          bank-reconciliation models.
        </Text>
      </Column>
      {!matterId ? (
        <Text onBackground="danger-weak">Set an active matter before calculating.</Text>
      ) : (
        <>
          <Select
            id="calculation-model"
            label="Approved model"
            value={versionId}
            onSelect={(value) => choose(value as string)}
            options={models
              .filter((model) => templates[model.model_code])
              .map((model) => ({
                value: model.current_version_id ?? "",
                label: `${model.model_code} — ${model.model_name}`,
              }))}
          />
          <Input
            id="run-name"
            label="Run name"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
          <Textarea
            id="calculation-inputs"
            label={`Inputs (JSON)${selected ? ` — ${selected.model_name}` : ""}`}
            value={inputs}
            lines={12}
            onChange={(event) => setInputs(event.target.value)}
          />
          <Textarea
            id="calculation-assumptions"
            label="Controlled assumptions (JSON)"
            value={assumptions}
            lines={6}
            onChange={(event) => setAssumptions(event.target.value)}
          />
          <Row horizontal="end">
            <Button onClick={run} loading={running} disabled={!versionId}>
              Calculate and preserve run
            </Button>
          </Row>
          <Table
            searchable
            striped
            data={{
              headers: [
                { key: "run", content: "Run" },
                { key: "status", content: "Status" },
                { key: "total", content: "Primary output" },
                { key: "narrative", content: "Narrative" },
              ],
              rows: runs.map((item) => [
                item.run_name ?? item.id,
                item.status,
                item.output_total == null
                  ? "—"
                  : `${item.output_currency ?? ""} ${item.output_total}`,
                item.narrative ?? "—",
              ]),
            }}
            emptyState={
              <Text onBackground="neutral-weak">No calculation runs for this matter.</Text>
            }
          />
        </>
      )}
    </Column>
  );
}
