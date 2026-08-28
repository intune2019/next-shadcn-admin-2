// lib/pm/types.ts + lib/pm/schemas.ts + lib/pm/actions.ts (combined for review).
// Mirrors migrations/0032_project_manager_module.sql.

import { z } from "zod";

// ============================================================================
// Domain types
// ============================================================================

export const projectStatuses = ["planning", "active", "on_hold", "completed", "cancelled"] as const;
export const taskStatuses = ["backlog", "todo", "in_progress", "in_review", "blocked", "done", "cancelled"] as const;
export const taskPriorities = ["low", "medium", "high", "urgent"] as const;
export const projectRoles = ["viewer", "member", "manager", "owner"] as const;
export const dependencyTypes = ["blocks", "blocked_by", "relates_to"] as const;

export interface Project {
  id: string;
  tenantId: string;
  matterId: string | null; // null = standalone/internal; set = engagement delivery plan
  projectName: string;
  description: string | null;
  status: (typeof projectStatuses)[number];
  startDate: string | null;
  dueDate: string | null;
  ownerUserId: string;
}

export interface Task {
  id: string;
  tenantId: string;
  projectId: string;
  milestoneId: string | null;
  parentTaskId: string | null;
  title: string;
  description: string | null;
  status: (typeof taskStatuses)[number];
  priority: (typeof taskPriorities)[number];
  assigneeUserId: string | null;
  reporterUserId: string;
  startDate: string | null;
  dueDate: string | null;
  estimatedHours: number | null;
  actualHours: number;
  sortOrder: number;
  completedAt: string | null;
}

export interface Milestone {
  id: string;
  projectId: string;
  milestoneName: string;
  dueDate: string | null;
  status: "not_started" | "in_progress" | "at_risk" | "completed";
  sortOrder: number;
}

// ============================================================================
// Zod schemas
// ============================================================================

export const createProjectFormSchema = z.object({
  tenantId: z.string().uuid(),
  projectName: z.string().min(1, "Project name is required").max(255),
  matterId: z.string().uuid().optional(), // omit for a standalone/internal project
  description: z.string().max(4000).optional(),
  dueDate: z.string().optional(),
});
export type CreateProjectFormValues = z.infer<typeof createProjectFormSchema>;

export const projectFormSchema = z.object({
  projectName: z.string().min(1).max(255),
  description: z.string().max(4000).optional(),
  status: z.enum(projectStatuses).default("planning"),
  startDate: z.string().optional(),
  dueDate: z.string().optional(),
}).refine(
  (v) => !v.startDate || !v.dueDate || v.startDate <= v.dueDate,
  { message: "Due date must be on or after the start date", path: ["dueDate"] }
);
export type ProjectFormValues = z.infer<typeof projectFormSchema>;

export const milestoneFormSchema = z.object({
  projectId: z.string().uuid(),
  milestoneName: z.string().min(1, "Milestone name is required").max(255),
  dueDate: z.string().optional(),
  sortOrder: z.coerce.number().int().default(0),
});
export type MilestoneFormValues = z.infer<typeof milestoneFormSchema>;

// The kanban card editor — this is what the shadcn <Sheet>/<Dialog> task
// detail form binds to. estimatedHours stays optional; actualHours is never
// editable from this form (it's a trigger-maintained rollup from time_entries).
export const taskFormSchema = z.object({
  projectId: z.string().uuid(),
  milestoneId: z.string().uuid().optional(),
  parentTaskId: z.string().uuid().optional(),
  title: z.string().min(1, "Title is required").max(255),
  description: z.string().max(8000).optional(),
  status: z.enum(taskStatuses).default("backlog"),
  priority: z.enum(taskPriorities).default("medium"),
  assigneeUserId: z.string().uuid().optional(),
  startDate: z.string().optional(),
  dueDate: z.string().optional(),
  estimatedHours: z.coerce.number().nonnegative().max(1000).optional(),
}).refine(
  (v) => !v.startDate || !v.dueDate || v.startDate <= v.dueDate,
  { message: "Due date must be on or after the start date", path: ["dueDate"] }
);
export type TaskFormValues = z.infer<typeof taskFormSchema>;

export const taskCommentFormSchema = z.object({
  taskId: z.string().uuid(),
  body: z.string().min(1, "Comment cannot be empty").max(4000),
});
export type TaskCommentFormValues = z.infer<typeof taskCommentFormSchema>;

export const taskDependencyFormSchema = z.object({
  taskId: z.string().uuid(),
  dependsOnTaskId: z.string().uuid(),
  dependencyType: z.enum(dependencyTypes).default("blocks"),
}).refine((v) => v.taskId !== v.dependsOnTaskId, {
  message: "A task cannot depend on itself",
  path: ["dependsOnTaskId"],
});
export type TaskDependencyFormValues = z.infer<typeof taskDependencyFormSchema>;

// Time entry — maps directly onto pm.log_time(task_id, minutes, note, billable).
// UI convention: capture hours (decimal) from the user, convert to minutes here.
export const timeEntryFormSchema = z.object({
  taskId: z.string().uuid(),
  hours: z.coerce.number().positive("Enter time greater than zero").max(24),
  note: z.string().max(1000).optional(),
  billable: z.boolean().default(true),
});
export type TimeEntryFormValues = z.infer<typeof timeEntryFormSchema>;

export const projectMemberFormSchema = z.object({
  projectId: z.string().uuid(),
  userId: z.string().uuid(),
  role: z.enum(projectRoles).default("member"),
});
export type ProjectMemberFormValues = z.infer<typeof projectMemberFormSchema>;

// ============================================================================
// Server actions
// ============================================================================

/*
"use server"
import { createClient } from "@/lib/supabase/server"
import { revalidatePath } from "next/cache"

export async function createProjectAction(input: unknown) {
  const parsed = createProjectFormSchema.safeParse(input)
  if (!parsed.success) return { ok: false, fieldErrors: parsed.error.flatten().fieldErrors }

  const supabase = await createClient()
  const { data, error } = await supabase.schema("pm").rpc("create_project", {
    p_tenant_id: parsed.data.tenantId,
    p_project_name: parsed.data.projectName,
    p_matter_id: parsed.data.matterId ?? null,
    p_description: parsed.data.description ?? null,
    p_due_date: parsed.data.dueDate ?? null,
  })

  if (error) return { ok: false, formErrors: [error.message] }
  revalidatePath("/projects")
  return { ok: true, projectId: data as string }
}

export async function updateTaskStatusAction(taskId: string, status: string) {
  // Drag-and-drop kanban move — validate against the enum, not free text,
  // even though this is a single-field update triggered by a UI event
  // rather than a full form submission.
  const parsed = z.enum(taskStatuses).safeParse(status)
  if (!parsed.success) return { ok: false, formErrors: ["Invalid status"] }

  const supabase = await createClient()
  const { error } = await supabase.schema("pm").from("tasks")
    .update({ status: parsed.data })
    .eq("id", taskId)
    // RLS (pm.has_project_access) does the real authorization; this .eq is
    // just the row selector.

  if (error) return { ok: false, formErrors: [error.message] }
  revalidatePath(`/projects`)
  return { ok: true }
}

export async function logTimeAction(input: unknown) {
  const parsed = timeEntryFormSchema.safeParse(input)
  if (!parsed.success) return { ok: false, fieldErrors: parsed.error.flatten().fieldErrors }

  const supabase = await createClient()
  const { data, error } = await supabase.schema("pm").rpc("log_time", {
    p_task_id: parsed.data.taskId,
    p_minutes: Math.round(parsed.data.hours * 60),
    p_note: parsed.data.note ?? null,
    p_billable: parsed.data.billable,
  })

  if (error) return { ok: false, formErrors: [error.message] }
  return { ok: true, timeEntryId: data as string }
}
*/
