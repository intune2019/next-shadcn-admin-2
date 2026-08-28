// lib/crm/types.ts + lib/crm/schemas.ts + lib/crm/actions.ts (combined for review;
// split into three files in your repo). Mirrors migrations/0031_crm_module.sql.

import { z } from "zod";

// ============================================================================
// Domain types (mirror crm.* tables — for hand-authored precision over
// `supabase gen types typescript`, which is still the source of truth for
// generated column types; keep both, this file is what forms bind to)
// ============================================================================

export const lifecycleStages = [
  "prospect", "lead", "opportunity", "client", "former_client", "disqualified",
] as const;

export const dealOutcomes = ["open", "won", "lost", "disqualified"] as const;

export const conflictCheckStatuses = [
  "not_started", "in_progress", "clear", "conflict_identified", "waived",
] as const;

export const activityTypes = ["call", "email", "meeting", "note", "task"] as const;

export interface Company {
  id: string;
  tenantId: string;
  legalName: string;
  dbaName: string | null;
  industry: string | null;
  website: string | null;
  phone: string | null;
  billingAddress: string | null;
  lifecycleStage: (typeof lifecycleStages)[number];
  source: string | null;
  ownerUserId: string | null;
  clientOrgId: string | null;
  createdAt: string;
}

export interface Contact {
  id: string;
  tenantId: string;
  companyId: string | null;
  firstName: string;
  lastName: string;
  title: string | null;
  email: string | null;
  phone: string | null;
  linkedinUrl: string | null;
  isPrimary: boolean;
  ownerUserId: string | null;
}

export interface Deal {
  id: string;
  tenantId: string;
  companyId: string;
  primaryContactId: string | null;
  pipelineId: string;
  stageId: string;
  dealName: string;
  engagementType: string | null;
  estimatedValue: number | null;
  currency: string;
  probabilityPct: number | null;
  expectedCloseDate: string | null;
  actualCloseDate: string | null;
  outcome: (typeof dealOutcomes)[number];
  lossReason: string | null;
  ownerUserId: string | null;
  conflictCheckStatus: (typeof conflictCheckStatuses)[number];
  convertedMatterId: string | null;
}

export interface Activity {
  id: string;
  tenantId: string;
  companyId: string | null;
  contactId: string | null;
  dealId: string | null;
  activityType: (typeof activityTypes)[number];
  subject: string | null;
  body: string | null;
  activityAt: string;
  dueAt: string | null;
  completedAt: string | null;
  ownerUserId: string | null;
}

// ============================================================================
// Zod schemas — bind these directly to React Hook Form via zodResolver.
// Only fields a human fills in the UI are here; tenant_id/created_by/etc are
// stamped server-side (app.tg_stamp_row / RLS), never trusted from the client.
// ============================================================================

export const companyFormSchema = z.object({
  legalName: z.string().min(1, "Legal name is required").max(255),
  dbaName: z.string().max(255).optional(),
  industry: z.string().max(120).optional(),
  website: z.string().url("Enter a valid URL").optional().or(z.literal("")),
  phone: z.string().max(40).optional(),
  billingAddress: z.string().max(500).optional(),
  lifecycleStage: z.enum(lifecycleStages).default("prospect"),
  source: z.string().max(120).optional(),
  ownerUserId: z.string().uuid().optional(),
});
export type CompanyFormValues = z.infer<typeof companyFormSchema>;

export const contactFormSchema = z.object({
  companyId: z.string().uuid().optional(),
  firstName: z.string().min(1, "First name is required").max(120),
  lastName: z.string().min(1, "Last name is required").max(120),
  title: z.string().max(120).optional(),
  email: z.string().email("Enter a valid email").optional().or(z.literal("")),
  phone: z.string().max(40).optional(),
  linkedinUrl: z.string().url().optional().or(z.literal("")),
  isPrimary: z.boolean().default(false),
});
export type ContactFormValues = z.infer<typeof contactFormSchema>;

export const dealFormSchema = z.object({
  companyId: z.string().uuid("Select a company"),
  primaryContactId: z.string().uuid().optional(),
  pipelineId: z.string().uuid("Select a pipeline"),
  stageId: z.string().uuid("Select a stage"),
  dealName: z.string().min(1, "Deal name is required").max(255),
  engagementType: z
    .enum(["fraud_exam", "litigation", "treasury", "monitorship", "receivership", "grc_audit"])
    .optional(),
  estimatedValue: z.coerce.number().nonnegative().optional(),
  currency: z.string().length(3).default("USD"),
  probabilityPct: z.coerce.number().min(0).max(100).optional(),
  expectedCloseDate: z.string().optional(), // ISO date string from a shadcn <Calendar>
  ownerUserId: z.string().uuid().optional(),
  conflictCheckStatus: z.enum(conflictCheckStatuses).default("not_started"),
});
export type DealFormValues = z.infer<typeof dealFormSchema>;

export const activityFormSchema = z.discriminatedUnion("activityType", [
  z.object({
    activityType: z.literal("task"),
    dealId: z.string().uuid().optional(),
    companyId: z.string().uuid().optional(),
    contactId: z.string().uuid().optional(),
    subject: z.string().min(1, "Task title is required").max(255),
    body: z.string().max(4000).optional(),
    dueAt: z.string().min(1, "Due date is required"), // required for tasks specifically
    ownerUserId: z.string().uuid().optional(),
  }),
  z.object({
    activityType: z.enum(["call", "email", "meeting", "note"]),
    dealId: z.string().uuid().optional(),
    companyId: z.string().uuid().optional(),
    contactId: z.string().uuid().optional(),
    subject: z.string().max(255).optional(),
    body: z.string().max(4000).optional(),
    activityAt: z.string().optional(),
    ownerUserId: z.string().uuid().optional(),
  }),
]);
export type ActivityFormValues = z.infer<typeof activityFormSchema>;

// The one non-trivial workflow: winning a deal. Kept as its own schema since
// it maps 1:1 onto the crm.win_deal(...) RPC signature.
export const winDealFormSchema = z.object({
  dealId: z.string().uuid(),
  createMatter: z.boolean().default(false),
  matterName: z.string().max(255).optional(),
  matterType: z
    .enum(["fraud_exam", "litigation", "treasury", "monitorship", "receivership", "grc_audit"])
    .optional(),
}).refine(
  (v) => !v.createMatter || (v.createMatter && v.matterType),
  { message: "Matter type is required when creating a matter", path: ["matterType"] }
);
export type WinDealFormValues = z.infer<typeof winDealFormSchema>;

// ============================================================================
// Server actions — "use server". Every RPC call re-validates with safeParse
// server-side per the platform's standing rule: client Zod is UX only.
// ============================================================================

/*
"use server"
import { createClient } from "@/lib/supabase/server"

export async function createCompanyAction(input: unknown) {
  const parsed = companyFormSchema.safeParse(input)
  if (!parsed.success) {
    return { ok: false, fieldErrors: parsed.error.flatten().fieldErrors }
  }
  const supabase = await createClient()
  const { data, error } = await supabase
    .schema("crm")
    .from("companies")
    .insert({
      legal_name: parsed.data.legalName,
      dba_name: parsed.data.dbaName || null,
      industry: parsed.data.industry || null,
      website: parsed.data.website || null,
      phone: parsed.data.phone || null,
      billing_address: parsed.data.billingAddress || null,
      lifecycle_stage: parsed.data.lifecycleStage,
      source: parsed.data.source || null,
      owner_user_id: parsed.data.ownerUserId || null,
      tenant_id: (await supabase.auth.getUser()).data.user?.app_metadata.tenant_id,
    })
    .select()
    .single()

  if (error) return { ok: false, formErrors: [error.message] }
  return { ok: true, data }
}

export async function winDealAction(input: unknown) {
  const parsed = winDealFormSchema.safeParse(input)
  if (!parsed.success) {
    return { ok: false, fieldErrors: parsed.error.flatten().fieldErrors }
  }
  const supabase = await createClient()
  // RPC, not a table write — this is the atomic company/matter bridge function.
  const { data, error } = await supabase.rpc("win_deal", {
    p_deal_id: parsed.data.dealId,
    p_create_matter: parsed.data.createMatter,
    p_matter_name: parsed.data.matterName ?? null,
    p_matter_type: parsed.data.matterType ?? null,
  }, { schema: "crm" } as never) // supabase-js: use .schema("crm").rpc(...) on v2.4x+

  if (error) return { ok: false, formErrors: [error.message] }
  return { ok: true, data } // { client_org_id, matter_id }
}
*/
