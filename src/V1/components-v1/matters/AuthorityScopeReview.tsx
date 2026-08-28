"use client";

import { createClient } from "@/lib/supabase/client";
import {
  Badge,
  Button,
  Card,
  Column,
  Heading,
  Line,
  Row,
  Table,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

interface Authority {
  id: string;
  authority_type: string;
  issuing_party: string | null;
  effective_date: string | null;
  expiration_date: string | null;
  mandate: string | null;
  extraction_status: string;
  extraction_metadata: Record<string, unknown>;
}

interface ScopeItem {
  id: string;
  clause_category: string | null;
  clause_text: string | null;
  in_scope: boolean;
  compliance_status: string;
  source_type: string;
}

export function AuthorityScopeReview({ matterId }: { matterId: string }) {
  const { addToast } = useToast();
  const [authority, setAuthority] = useState<Authority | null>(null);
  const [scope, setScope] = useState<ScopeItem[]>([]);
  const [latestDecision, setLatestDecision] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [working, setWorking] = useState("");

  const load = useCallback(async () => {
    const supabase = createClient();
    const [authorityResult, scopeResult, approvalResult] = await Promise.all([
      supabase
        .schema("core")
        .from("authority_instruments")
        .select(
          "id,authority_type,issuing_party,effective_date,expiration_date,mandate,extraction_status,extraction_metadata",
        )
        .eq("matter_id", matterId)
        .eq("record_status", "active")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .schema("core")
        .from("scope_items")
        .select("id,clause_category,clause_text,in_scope,compliance_status,source_type")
        .eq("matter_id", matterId)
        .eq("record_status", "active")
        .order("created_at"),
      supabase
        .schema("core")
        .from("scope_approvals")
        .select("decision")
        .eq("matter_id", matterId)
        .order("scope_version", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);
    setAuthority((authorityResult.data as Authority | null) ?? null);
    setScope((scopeResult.data as ScopeItem[] | null) ?? []);
    setLatestDecision((approvalResult.data as { decision?: string } | null)?.decision ?? null);
  }, [matterId]);

  useEffect(() => {
    load();
  }, [load]);

  async function parseAuthority() {
    if (!authority) return;
    setWorking("parse");
    const supabase = createClient();
    const { data, error } = await supabase
      .schema("core")
      .rpc("parse_authority_instrument", { p_authority_id: authority.id });
    setWorking("");
    if (error) return addToast({ variant: "danger", message: error.message });
    const counts = data as { scope_items?: number; reporting_obligations?: number };
    addToast({
      variant: "success",
      message: `Extracted ${counts.scope_items ?? 0} scope clauses and ${counts.reporting_obligations ?? 0} reporting obligations.`,
    });
    load();
  }

  async function decide(decision: "approved" | "rejected" | "revision_requested") {
    setWorking(decision);
    const supabase = createClient();
    const { error } = await supabase
      .schema("core")
      .rpc("decide_scope", { p_matter_id: matterId, p_decision: decision, p_note: note || null });
    setWorking("");
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({
      variant: "success",
      message:
        decision === "approved"
          ? "Scope approved and workflows activated."
          : "Scope decision preserved.",
    });
    load();
  }

  const rows = scope.map((item) => [
    item.clause_category ?? "duty",
    item.clause_text ?? "—",
    item.in_scope ? "In scope" : "Out of scope",
    item.compliance_status,
    item.source_type === "manual" ? "Manual" : "Extracted",
  ]);

  return (
    <Column fillWidth gap="24">
      <Column gap="8">
        <Row gap="8" vertical="center">
          <Badge onBackground={latestDecision === "approved" ? "success-strong" : "warning-strong"}>
            {latestDecision ?? "awaiting review"}
          </Badge>
        </Row>
        <Heading variant="heading-strong-l">Authority and scope review</Heading>
        <Text onBackground="neutral-weak">
          Verify system-extracted duties, limits, deadlines, and reporting obligations before
          activating analytics.
        </Text>
      </Column>

      {!authority ? (
        <Card padding="20" border="neutral-alpha-medium">
          <Text onBackground="danger-weak">
            No authority instrument is recorded. Add one before scope approval.
          </Text>
        </Card>
      ) : (
        <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
          <Row horizontal="between" vertical="center" wrap gap="12">
            <Column gap="4">
              <Heading variant="heading-strong-s">
                {authority.authority_type.replaceAll("_", " ")}
              </Heading>
              <Text onBackground="neutral-weak">
                {authority.issuing_party ?? "Issuing party not specified"} · extraction{" "}
                {authority.extraction_status}
              </Text>
            </Column>
            <Button
              onClick={parseAuthority}
              loading={working === "parse"}
              disabled={!authority.mandate}
            >
              Extract obligations
            </Button>
          </Row>
          <Text>{authority.mandate || "No mandate text supplied."}</Text>
        </Card>
      )}

      <Line />
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "category", content: "Category" },
            { key: "clause", content: "Clause" },
            { key: "scope", content: "Scope" },
            { key: "status", content: "Status" },
            { key: "source", content: "Source" },
          ],
          rows,
        }}
        emptyState={
          <Text onBackground="neutral-weak">
            Run extraction to propose scope clauses for review.
          </Text>
        }
      />
      <Textarea
        id="scope-decision-note"
        label="Reviewer decision note"
        lines={4}
        value={note}
        onChange={(event) => setNote(event.target.value)}
        description="Required by practice policy when rejecting or requesting revision; recommended for every approval."
      />
      <Row horizontal="between" gap="12" wrap>
        <Link href={`/app/matters/${matterId}`} style={{ textDecoration: "none" }}>
          <Button variant="secondary">Return to matter</Button>
        </Link>
        <Row gap="8" wrap>
          <Button
            variant="secondary"
            onClick={() => decide("rejected")}
            loading={working === "rejected"}
          >
            Reject
          </Button>
          <Button
            variant="secondary"
            onClick={() => decide("revision_requested")}
            loading={working === "revision_requested"}
          >
            Request revision
          </Button>
          <Button
            onClick={() => decide("approved")}
            loading={working === "approved"}
            disabled={!scope.length}
          >
            Approve and activate
          </Button>
        </Row>
      </Row>
    </Column>
  );
}
