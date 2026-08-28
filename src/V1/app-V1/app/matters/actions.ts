"use server";

import { createClient as createServerClient } from "@/lib/supabase/server";

/**
 * Matter provisioning is performed by a SECURITY DEFINER database function.
 * The function requires the caller to already hold matter_admin access in the
 * tenant and creates the matter plus its first access grant atomically.
 */
export async function createMatter(input: {
  tenantId: string;
  matterName: string;
  matterType: string;
  confidentiality?: string;
  clientOrgId?: string | null;
}): Promise<{ id: string; matterNumber: string } | { error: string }> {
  const authed = await createServerClient();
  const {
    data: { user },
  } = await authed.auth.getUser();
  if (!user) return { error: "Not signed in." };

  if (!input.matterName.trim()) return { error: "Matter name is required." };
  if (!input.matterType.trim()) return { error: "Matter type is required." };

  const { data, error } = await authed.schema("core").rpc("provision_matter", {
    p_tenant_id: input.tenantId,
    p_matter_name: input.matterName.trim(),
    p_matter_type: input.matterType.trim(),
    p_confidentiality: input.confidentiality || "attorney_work_product",
    p_client_org_id: input.clientOrgId || null,
  });

  const matter = Array.isArray(data) ? data[0] : data;
  if (error || !matter) {
    return { error: error?.message ?? "Failed to create matter." };
  }

  return { id: matter.id as string, matterNumber: matter.matter_number as string };
}

export interface MatterIntakeInput {
  tenantId: string;
  matterName: string;
  matterType: string;
  jurisdiction: string;
  confidentiality: string;
  riskLevel: string;
  modules: string[];
  parties: { party_name: string; party_role: string; counsel?: string }[];
  authority: {
    authority_type: string;
    issuing_party?: string;
    effective_date?: string;
    expiration_date?: string;
    mandate?: string;
  };
  deadlines: { deadline_type: string; due_at: string }[];
  conflictAttestation: string;
  conflictIdentified: boolean;
  retentionCategory: string;
}

export async function createMatterIntake(
  input: MatterIntakeInput,
): Promise<{ id: string; matterNumber: string } | { error: string }> {
  const authed = await createServerClient();
  const {
    data: { user },
  } = await authed.auth.getUser();
  if (!user) return { error: "Not signed in." };
  if (!input.tenantId) return { error: "Set an active tenant before creating a matter." };
  if (!input.matterName.trim()) return { error: "Matter name is required." };
  if (!input.matterType.trim()) return { error: "Engagement type is required." };
  if (!input.modules.length) return { error: "Select at least one service module." };

  const { data, error } = await authed.schema("core").rpc("provision_matter_intake", {
    p_tenant_id: input.tenantId,
    p_matter_name: input.matterName.trim(),
    p_matter_type: input.matterType.trim(),
    p_jurisdiction: input.jurisdiction.trim(),
    p_confidentiality: input.confidentiality,
    p_risk_level: input.riskLevel,
    p_modules: input.modules,
    p_parties: input.parties.filter((party) => party.party_name.trim()),
    p_authority: input.authority,
    p_deadlines: input.deadlines.filter((deadline) => deadline.due_at),
    p_conflict_attestation: input.conflictAttestation.trim(),
    p_conflict_identified: input.conflictIdentified,
    p_retention_category: input.retentionCategory,
  });
  const matter = Array.isArray(data) ? data[0] : data;
  if (error || !matter) return { error: error?.message ?? "Failed to create matter intake." };
  return { id: matter.id as string, matterNumber: matter.matter_number as string };
}
