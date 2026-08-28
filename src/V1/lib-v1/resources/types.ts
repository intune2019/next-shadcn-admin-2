export type FieldType = "text" | "textarea" | "number" | "date" | "select" | "checkbox" | "relation";

export interface RelationConfig {
  /** Postgres schema of the related table, e.g. "evidence" */
  schema: string;
  table: string;
  /** Column whose value becomes the option label, e.g. "human_evidence_no" */
  labelKey: string;
  /** Column stored as the field's value — almost always "id" */
  valueKey: string;
  /** Scope the option list to the active matter (most FKs are matter-scoped). */
  matterScoped?: boolean;
}

export interface FieldConfig {
  key: string;
  label: string;
  type: FieldType;
  required?: boolean;
  options?: { label: string; value: string }[];
  defaultValue?: string | number | boolean;
  help?: string;
  /** For type "relation": which table to pick a row from. */
  relation?: RelationConfig;
  /**
   * Filled silently from the active tenant/matter context instead of being
   * rendered as an input. Almost every table in this schema requires
   * tenant_id and/or matter_id — see TenantProvider.
   */
  auto?: "tenant_id" | "matter_id" | "current_user_id" | "now";
}

export interface ListColumn {
  key: string;
  label: string;
  width?: string;
}

export interface ResourceConfig {
  /** Postgres schema, e.g. "core" */
  schema: string;
  table: string;
  /** URL segment under /app/<slug> */
  slug: string;
  label: string;
  pluralLabel: string;
  description?: string;
  /** Append-only / global reference tables: hide the create form. */
  readOnly?: boolean;
  listColumns: ListColumn[];
  /** Fields collected by the create form. Omit entirely for readOnly resources. */
  fields: FieldConfig[];
  /**
   * Fields the detail page can update after creation — status transitions,
   * reviewer sign-off, etc. Distinct from `fields` because what's editable
   * post-creation is rarely the same set collected at creation. Omit for
   * resources with no post-creation edits (append-only, or nothing to change).
   */
  updateFields?: FieldConfig[];
  orderBy?: { column: string; ascending?: boolean };
}
