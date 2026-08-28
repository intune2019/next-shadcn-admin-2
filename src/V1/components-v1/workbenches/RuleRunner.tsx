"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Button,
  Column,
  Heading,
  Row,
  Select,
  Table,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
import { useCallback, useEffect, useState } from "react";

interface Rule {
  current_version_id: string | null;
  rule_code: string;
  rule_name: string;
}
interface Run {
  id: string;
  status: string;
  hits_created: number | null;
  records_tested: number | null;
  started_at: string;
}

export function RuleRunner() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [rules, setRules] = useState<Rule[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [versionId, setVersionId] = useState("");
  const [parameters, setParameters] = useState("{}");
  const [running, setRunning] = useState(false);

  const load = useCallback(async () => {
    const supabase = createClient();
    const [{ data: ruleData }, { data: runData }] = await Promise.all([
      supabase
        .schema("rules")
        .from("rule_definitions")
        .select("current_version_id,rule_code,rule_name")
        .not("current_version_id", "is", null)
        .order("rule_code"),
      matterId
        ? supabase
            .schema("rules")
            .from("rule_runs")
            .select("id,status,hits_created,records_tested,started_at")
            .eq("matter_id", matterId)
            .order("started_at", { ascending: false })
            .limit(20)
        : Promise.resolve({ data: [] }),
    ]);
    setRules((ruleData as Rule[] | null) ?? []);
    setRuns((runData as Run[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);

  async function run() {
    if (!matterId || !versionId) return;
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(parameters);
    } catch {
      return addToast({ variant: "danger", message: "Parameters must be valid JSON." });
    }
    setRunning(true);
    const { data, error } = await createClient().schema("rules").rpc("execute_rule_version", {
      p_rule_version_id: versionId,
      p_matter_id: matterId,
      p_parameters: parsed,
    });
    setRunning(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `Rule run ${data} completed.` });
    load();
  }

  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Detection rule runner</Heading>
        <Text onBackground="neutral-weak">
          Execute a current, checksummed rule version against the active matter. Hits are preserved
          and grouped into an alert.
        </Text>
      </Column>
      {!matterId ? (
        <Text onBackground="danger-weak">Set an active matter before running rules.</Text>
      ) : (
        <>
          <Select
            id="rule-version"
            label="Current rule version"
            value={versionId}
            onSelect={(value) => setVersionId(value as string)}
            options={rules.map((rule) => ({
              value: rule.current_version_id ?? "",
              label: `${rule.rule_code} — ${rule.rule_name}`,
            }))}
          />
          <Textarea
            id="rule-parameters"
            label="Parameter overrides (JSON)"
            value={parameters}
            lines={6}
            onChange={(event) => setParameters(event.target.value)}
          />
          <Row horizontal="end">
            <Button onClick={run} loading={running} disabled={!versionId}>
              Run selected rule
            </Button>
          </Row>
          <Table
            searchable
            striped
            data={{
              headers: [
                { key: "id", content: "Run" },
                { key: "status", content: "Status" },
                { key: "hits", content: "Hits" },
                { key: "tested", content: "Tested" },
                { key: "started", content: "Started" },
              ],
              rows: runs.map((item) => [
                item.id,
                item.status,
                String(item.hits_created ?? 0),
                String(item.records_tested ?? 0),
                new Date(item.started_at).toLocaleString(),
              ]),
            }}
            emptyState={<Text onBackground="neutral-weak">No rule runs for this matter.</Text>}
          />
        </>
      )}
    </Column>
  );
}
