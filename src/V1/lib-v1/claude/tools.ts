import type Anthropic from "@anthropic-ai/sdk";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Read-only lookups into the active matter's own evidentiary record, run
 * through the caller's own Supabase session — not a service-role client.
 * RLS (app.has_matter_access) applies exactly as it would to any other read
 * in the app, so Veritas structurally cannot see anything the signed-in user
 * couldn't already see themselves. Every tool is capped at 50 rows: this is
 * a research aid pointing the reviewer at the right records, not a full
 * data export.
 */

const ROW_LIMIT = 50;

export function buildMatterTools(supabase: SupabaseClient, matterId: string) {
  const definitions: Anthropic.Tool[] = [
    {
      name: "list_evidence",
      description:
        "List evidence items in the matter: evidence number, title, type, custody/legal-hold status, confidentiality. Use before citing a specific evidence number.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "list_facts",
      description:
        "List discrete sourced facts recorded in the matter, with fact type and confidence level. Facts are the evidentiary basis findings must cite.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "list_findings",
      description:
        "List investigative findings: title, conclusion status, classification, financial impact. A finding cannot be 'supported' or 'final' without a reviewer and a linked fact — the schema enforces this, not just convention.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "get_finding_detail",
      description:
        "Get one finding's full detail plus every fact cited as its source (and any explicitly marked as contrary evidence). Use this before assessing whether a finding's conclusion is actually supported by what's on record.",
      input_schema: {
        type: "object",
        properties: { finding_id: { type: "string", description: "UUID of the finding" } },
        required: ["finding_id"],
        additionalProperties: false,
      },
    },
    {
      name: "list_allegations",
      description:
        "List allegations in the matter: allegation number, status, scheme category, reported conduct. The top of the allegation -> lead -> fact -> finding hierarchy.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "list_transactions",
      description: "List canonical financial transactions recorded for the matter.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
      name: "list_entities",
      description:
        "List entities (people, organizations, accounts, devices, assets) recorded in the matter.",
      input_schema: { type: "object", properties: {}, additionalProperties: false },
    },
  ];

  async function execute(name: string, input: Record<string, unknown>): Promise<string> {
    switch (name) {
      case "list_evidence": {
        const { data, error } = await supabase
          .schema("evidence")
          .from("evidence_items")
          .select("human_evidence_no, title, evidence_type, status, legal_hold_status, confidentiality")
          .eq("matter_id", matterId)
          .order("human_evidence_no")
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      case "list_facts": {
        const { data, error } = await supabase
          .schema("investigation")
          .from("facts")
          .select("id, statement, fact_type, confidence, contrary_evidence")
          .eq("matter_id", matterId)
          .order("created_at", { ascending: false })
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      case "list_findings": {
        const { data, error } = await supabase
          .schema("investigation")
          .from("findings")
          .select("id, title, conclusion_status, classification, methodology, financial_impact, currency, reviewed_by")
          .eq("matter_id", matterId)
          .order("created_at", { ascending: false })
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      case "get_finding_detail": {
        const findingId = input.finding_id as string;
        const { data: finding, error: findingError } = await supabase
          .schema("investigation")
          .from("findings")
          .select("*")
          .eq("id", findingId)
          .eq("matter_id", matterId)
          .single();
        if (findingError) return jsonResult(null, findingError);
        const { data: sources, error: sourcesError } = await supabase
          .schema("investigation")
          .from("finding_sources")
          .select("is_contrary, facts(id, statement, fact_type, confidence)")
          .eq("finding_id", findingId);
        return jsonResult({ finding, sources }, sourcesError);
      }
      case "list_allegations": {
        const { data, error } = await supabase
          .schema("investigation")
          .from("allegations")
          .select("allegation_no, status, scheme_category, reported_conduct")
          .eq("matter_id", matterId)
          .order("allegation_no")
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      case "list_transactions": {
        const { data, error } = await supabase
          .schema("canonical")
          .from("transactions")
          .select("id, transaction_type, amount_original, currency_original, created_at")
          .eq("matter_id", matterId)
          .order("created_at", { ascending: false })
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      case "list_entities": {
        const { data, error } = await supabase
          .schema("canonical")
          .from("entities")
          .select("id, entity_type, name_normalized")
          .eq("matter_id", matterId)
          .order("created_at", { ascending: false })
          .limit(ROW_LIMIT);
        return jsonResult(data, error);
      }
      default:
        return JSON.stringify({ error: `Unknown tool: ${name}` });
    }
  }

  return { definitions, execute };
}

function jsonResult(data: unknown, error: { message: string } | null): string {
  if (error) return JSON.stringify({ error: error.message });
  return JSON.stringify(data ?? []);
}
