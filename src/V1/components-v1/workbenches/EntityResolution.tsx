"use client";

import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import { Button, Column, Heading, Input, Row, Table, Text, useToast } from "@once-ui-system/core";
import { useCallback, useEffect, useState } from "react";

interface Candidate {
  id: string;
  entity_id_a: string;
  entity_id_b: string;
  match_score: number;
  match_basis: string[] | null;
  candidate_type: string;
  review_status: string;
}
interface Entity {
  id: string;
  display_name: string | null;
  name_normalized: string | null;
}

export function EntityResolution() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [minimum, setMinimum] = useState("35");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [names, setNames] = useState<Record<string, string>>({});
  const [running, setRunning] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) {
      setCandidates([]);
      return;
    }
    const supabase = createClient();
    const [{ data: candidateData }, { data: entityData }] = await Promise.all([
      supabase
        .schema("identity")
        .from("entity_match_candidates")
        .select("id,entity_id_a,entity_id_b,match_score,match_basis,candidate_type,review_status")
        .eq("matter_id", matterId)
        .eq("generated_by", "weighted_v1")
        .order("match_score", { ascending: false }),
      supabase
        .schema("canonical")
        .from("entities")
        .select("id,display_name,name_normalized")
        .eq("matter_id", matterId),
    ]);
    setCandidates((candidateData as Candidate[] | null) ?? []);
    setNames(
      Object.fromEntries(
        ((entityData as Entity[] | null) ?? []).map((entity) => [
          entity.id,
          entity.display_name ?? entity.name_normalized ?? entity.id,
        ]),
      ),
    );
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function generate() {
    if (!matterId) return;
    setRunning(true);
    const { data, error } = await createClient()
      .schema("identity")
      .rpc("generate_match_candidates", {
        p_matter_id: matterId,
        p_min_score: Number(minimum) || 35,
      });
    setRunning(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({
      variant: "success",
      message: `${data ?? 0} weighted candidates generated or refreshed.`,
    });
    load();
  }
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Entity resolution</Heading>
        <Text onBackground="neutral-weak">
          Explainable weighted scoring: normalized name 45%, alias 15%, address 15%, contact 10%,
          and bank identifier 15%. Candidates are never auto-merged.
        </Text>
      </Column>
      {!matterId ? (
        <Text onBackground="danger-weak">Set an active matter first.</Text>
      ) : (
        <>
          <Row gap="12" vertical="end" wrap>
            <Input
              id="minimum-score"
              label="Minimum score (0–100)"
              value={minimum}
              onChange={(event) => setMinimum(event.target.value)}
            />
            <Button onClick={generate} loading={running}>
              Generate candidates
            </Button>
          </Row>
          <Table
            searchable
            striped
            data={{
              headers: [
                { key: "a", content: "Entity A" },
                { key: "b", content: "Entity B" },
                { key: "score", content: "Score" },
                { key: "basis", content: "Basis" },
                { key: "status", content: "Review status" },
              ],
              rows: candidates.map((item) => [
                names[item.entity_id_a] ?? item.entity_id_a,
                names[item.entity_id_b] ?? item.entity_id_b,
                `${item.match_score}/100`,
                item.match_basis?.join(", ") ?? "—",
                `${item.candidate_type} · ${item.review_status}`,
              ]),
            }}
            emptyState={<Text onBackground="neutral-weak">No weighted match candidates yet.</Text>}
          />
        </>
      )}
    </Column>
  );
}
