"use client";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Badge,
  Button,
  Card,
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
import { useCallback, useEffect, useState } from "react";

export function DataIngestionWorkbench() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [sets, setSets] = useState<Record<string, unknown>[]>([]);
  const [exceptions, setExceptions] = useState<Record<string, unknown>[]>([]);
  const [recons, setRecons] = useState<Record<string, unknown>[]>([]);
  const [selected, setSelected] = useState("");
  const [note, setNote] = useState("");
  const [working, setWorking] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [d, e, r] = await Promise.all([
      db
        .schema("evidence")
        .from("dataset_versions")
        .select("id,readiness_status,record_count,control_total,period_start,period_end,created_at")
        .eq("matter_id", matterId)
        .order("created_at", { ascending: false }),
      db
        .schema("quality")
        .from("mapping_exceptions")
        .select(
          "id,dataset_version_id,exception_type,required_action,exception_status,field_name,detail",
        )
        .eq("matter_id", matterId)
        .in("exception_status", ["open", "in_review"]),
      db
        .schema("quality")
        .from("reconciliations")
        .select("id,dataset_version_id,reconciliation_type,source_value,canonical_value,result")
        .eq("matter_id", matterId),
    ]);
    setSets((d.data as Record<string, unknown>[] | null) ?? []);
    setExceptions((e.data as Record<string, unknown>[] | null) ?? []);
    setRecons((r.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function approve() {
    if (!selected) return;
    setWorking(true);
    const { error } = await createClient()
      .schema("evidence")
      .rpc("approve_dataset_for_analytics", { p_dataset_id: selected, p_note: note || null });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({
      variant: "success",
      message: "Dataset approved for analytics; attestation preserved.",
    });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Data ingestion and readiness</Heading>
        <Text onBackground="neutral-weak">
          Dataset versions, mapping exceptions, reconciliations, and independent approval.
        </Text>
      </Column>
      <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
        <Select
          id="dataset-approval"
          label="Dataset version"
          value={selected}
          onSelect={(v) => setSelected(v as string)}
          options={sets.map((s) => ({
            value: String(s.id),
            label: `${String(s.id).slice(0, 8)} · ${String(s.readiness_status)} · ${String(s.record_count ?? 0)} rows`,
          }))}
        />
        <Textarea
          id="dataset-attestation"
          label="Approval attestation"
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
        <Button onClick={approve} loading={working} disabled={!selected}>
          Approve for analytics
        </Button>
      </Card>
      <Heading variant="heading-strong-s">Dataset versions</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "id", content: "Version" },
            { key: "status", content: "Readiness" },
            { key: "rows", content: "Rows" },
            { key: "total", content: "Control total" },
            { key: "period", content: "Period" },
          ],
          rows: sets.map((s) => [
            String(s.id).slice(0, 8),
            String(s.readiness_status),
            String(s.record_count ?? "—"),
            String(s.control_total ?? "—"),
            `${String(s.period_start ?? "—")} – ${String(s.period_end ?? "—")}`,
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Blocking and review exceptions</Heading>
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "type", content: "Type" },
            { key: "action", content: "Required action" },
            { key: "field", content: "Field" },
            { key: "status", content: "Status" },
            { key: "detail", content: "Detail" },
          ],
          rows: exceptions.map((e) => [
            String(e.exception_type),
            String(e.required_action),
            String(e.field_name ?? "—"),
            String(e.exception_status),
            String(e.detail ?? "—"),
          ]),
        }}
        emptyState={<Text onBackground="neutral-weak">No open mapping exceptions.</Text>}
      />
      <Heading variant="heading-strong-s">Reconciliation evidence</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "type", content: "Type" },
            { key: "source", content: "Source" },
            { key: "canonical", content: "Canonical" },
            { key: "result", content: "Result" },
          ],
          rows: recons.map((r) => [
            String(r.reconciliation_type),
            String(r.source_value ?? "—"),
            String(r.canonical_value ?? "—"),
            String(r.result),
          ]),
        }}
      />
    </Column>
  );
}

export function ReportGovernanceWorkbench() {
  const { matterId, tenantId } = useTenant();
  const { addToast } = useToast();
  const [reports, setReports] = useState<Record<string, unknown>[]>([]);
  const [comments, setComments] = useState<Record<string, unknown>[]>([]);
  const [distributions, setDistributions] = useState<Record<string, unknown>[]>([]);
  const [reportId, setReportId] = useState("");
  const [commentId, setCommentId] = useState("");
  const [distributionId, setDistributionId] = useState("");
  const [text, setText] = useState("");
  const [recipient, setRecipient] = useState("");
  const [working, setWorking] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [r, c, d] = await Promise.all([
      db
        .schema("reporting")
        .from("reports")
        .select("id,title,report_type,version,status")
        .eq("matter_id", matterId),
      db
        .schema("reporting")
        .from("report_comments")
        .select("id,report_id,comment_text,status,created_at")
        .eq("matter_id", matterId)
        .order("created_at", { ascending: false }),
      db
        .schema("reporting")
        .from("distribution_log")
        .select("id,report_id,recipient_name,delivery_method,delivery_status,distributed_at")
        .eq("matter_id", matterId)
        .order("created_at", { ascending: false }),
    ]);
    setReports((r.data as Record<string, unknown>[] | null) ?? []);
    setComments((c.data as Record<string, unknown>[] | null) ?? []);
    setDistributions((d.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function createReport(reportType: string, title: string) {
    if (!tenantId || !matterId) return;
    setWorking(true);
    const { data, error } = await createClient()
      .schema("reporting")
      .from("reports")
      .insert({
        tenant_id: tenantId,
        matter_id: matterId,
        report_type: reportType,
        title,
        status: "outline",
      })
      .select("id")
      .single();
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    setReportId(data.id);
    addToast({ variant: "success", message: `${title} started.` });
    load();
  }
  async function comment() {
    if (!tenantId || !matterId || !reportId || !text) return;
    setWorking(true);
    const { error } = await createClient().schema("reporting").from("report_comments").insert({
      tenant_id: tenantId,
      matter_id: matterId,
      report_id: reportId,
      comment_text: text,
    });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    setText("");
    addToast({ variant: "success", message: "Review comment preserved." });
    load();
  }
  async function prepare() {
    if (!tenantId || !matterId || !reportId || !recipient) return;
    setWorking(true);
    const { error } = await createClient().schema("reporting").from("distribution_log").insert({
      tenant_id: tenantId,
      matter_id: matterId,
      report_id: reportId,
      recipient_name: recipient,
      delivery_method: "secure_download",
      delivery_status: "prepared",
    });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: "Controlled distribution entry prepared." });
    load();
  }
  async function reportAction(action: "assemble" | "approve" | "sign" | "resolve" | "issue") {
    const db = createClient();
    setWorking(true);
    let error: { message: string } | null = null;
    if (action === "assemble")
      ({ error } = await db.schema("reporting").rpc("assemble_report", { p_report_id: reportId }));
    if (action === "approve")
      ({ error } = await db.schema("reporting").rpc("decide_report", {
        p_report_id: reportId,
        p_decision: "approved",
        p_role: "technical_reviewer",
        p_note: "Independent technical review completed.",
      }));
    if (action === "sign")
      ({ error } = await db.schema("reporting").rpc("sign_report", {
        p_report_id: reportId,
        p_signer_role: "engagement_lead",
      }));
    if (action === "resolve")
      ({ error } = await db
        .schema("reporting")
        .from("report_comments")
        .update({
          status: "resolved",
          resolved_at: new Date().toISOString(),
        })
        .eq("id", commentId));
    if (action === "issue")
      ({ error } = await db.schema("reporting").rpc("issue_distribution", {
        p_distribution_id: distributionId,
      }));
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: `${action} completed and preserved.` });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Report review and distribution</Heading>
        <Text onBackground="neutral-weak">
          Collaborative comments, editions, approvals, signatures, and controlled recipient logs.
        </Text>
      </Column>
      <Column gap="12">
        <Heading variant="heading-strong-s">Create new</Heading>
        <Row gap="12" wrap>
          {[
            ["fraud_exam", "Fraud Examination Report"],
            ["executive_memo", "Executive Findings Memo"],
            ["damages", "Loss and Recovery Schedule"],
            ["treasury_governance", "Treasury Governance Report"],
            ["monitor_report", "Monitor Status Report"],
            ["court_exhibits", "Court Exhibit Package"],
          ].map(([type, title]) => (
            <Card
              key={type}
              padding="16"
              border="neutral-alpha-medium"
              direction="column"
              gap="8"
              style={{ minWidth: 210 }}
            >
              <Heading variant="heading-strong-s">{title}</Heading>
              <Text variant="body-default-xs" onBackground="neutral-weak">
                Starts from approved findings, evidence, and calculations.
              </Text>
              <Button
                size="s"
                variant="secondary"
                onClick={() => createReport(type, title)}
                loading={working}
              >
                Create report
              </Button>
            </Card>
          ))}
        </Row>
      </Column>
      <Heading variant="heading-strong-s">In progress and issued reports</Heading>
      <Select
        id="governed-report"
        label="Report"
        value={reportId}
        onSelect={(v) => setReportId(v as string)}
        options={reports.map((r) => ({
          value: String(r.id),
          label: `${String(r.title)} · v${String(r.version)} · ${String(r.status)}`,
        }))}
      />
      <Row gap="8" wrap>
        <Button
          variant="secondary"
          onClick={() => reportAction("assemble")}
          disabled={!reportId}
          loading={working}
        >
          Assemble approved content
        </Button>
        <Button
          variant="secondary"
          onClick={() => reportAction("approve")}
          disabled={!reportId}
          loading={working}
        >
          Approve report
        </Button>
        <Button onClick={() => reportAction("sign")} disabled={!reportId} loading={working}>
          Sign approved report
        </Button>
      </Row>
      <Row gap="16" wrap>
        <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12" flex={1}>
          <Heading variant="heading-strong-s">Add review comment</Heading>
          <Textarea
            id="report-comment"
            label="Comment"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
          <Button onClick={comment} loading={working} disabled={!reportId || !text}>
            Add comment
          </Button>
        </Card>
        <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12" flex={1}>
          <Heading variant="heading-strong-s">Prepare distribution</Heading>
          <Input
            id="recipient"
            label="Recipient"
            value={recipient}
            onChange={(e) => setRecipient(e.target.value)}
          />
          <Button onClick={prepare} loading={working} disabled={!reportId || !recipient}>
            Prepare secure delivery
          </Button>
        </Card>
      </Row>
      <Heading variant="heading-strong-s">Open review history</Heading>
      <Row gap="12" vertical="end">
        <Select
          id="resolve-comment"
          label="Comment to resolve"
          value={commentId}
          onSelect={(v) => setCommentId(v as string)}
          options={comments
            .filter((c) => c.status === "open")
            .map((c) => ({ value: String(c.id), label: String(c.comment_text).slice(0, 80) }))}
        />
        <Button variant="secondary" onClick={() => reportAction("resolve")} disabled={!commentId}>
          Resolve comment
        </Button>
      </Row>
      <Table
        striped
        data={{
          headers: [
            { key: "report", content: "Report" },
            { key: "comment", content: "Comment" },
            { key: "status", content: "Status" },
            { key: "at", content: "Recorded" },
          ],
          rows: comments.map((c) => [
            String(c.report_id).slice(0, 8),
            String(c.comment_text),
            String(c.status),
            String(c.created_at),
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Distribution ledger</Heading>
      <Row gap="12" vertical="end">
        <Select
          id="issue-distribution"
          label="Prepared distribution"
          value={distributionId}
          onSelect={(v) => setDistributionId(v as string)}
          options={distributions
            .filter((d) => d.delivery_status === "prepared")
            .map((d) => ({
              value: String(d.id),
              label: `${String(d.recipient_name)} · ${String(d.delivery_method)}`,
            }))}
        />
        <Button onClick={() => reportAction("issue")} disabled={!distributionId}>
          Issue signed report
        </Button>
      </Row>
      <Table
        striped
        data={{
          headers: [
            { key: "report", content: "Report" },
            { key: "recipient", content: "Recipient" },
            { key: "method", content: "Method" },
            { key: "status", content: "Status" },
            { key: "at", content: "Distributed" },
          ],
          rows: distributions.map((d) => [
            String(d.report_id).slice(0, 8),
            String(d.recipient_name),
            String(d.delivery_method),
            String(d.delivery_status),
            String(d.distributed_at ?? "—"),
          ]),
        }}
      />
    </Column>
  );
}

export function CourtOperationsWorkbench() {
  const { matterId, tenantId } = useTenant();
  const { addToast } = useToast();
  const [assets, setAssets] = useState<Record<string, unknown>[]>([]);
  const [fees, setFees] = useState<Record<string, unknown>[]>([]);
  const [logs, setLogs] = useState<Record<string, unknown>[]>([]);
  const [kind, setKind] = useState("asset");
  const [title, setTitle] = useState("");
  const [amount, setAmount] = useState("");
  const [working, setWorking] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) return;
    const db = createClient();
    const [a, f, l] = await Promise.all([
      db
        .schema("court")
        .from("assets")
        .select("id,asset_number,asset_type,description,estimated_value,status")
        .eq("matter_id", matterId),
      db
        .schema("court")
        .from("fees_expenses")
        .select("id,professional_ref,entry_date,entry_type,description,amount,status")
        .eq("matter_id", matterId),
      db
        .schema("court")
        .from("neutrality_log")
        .select("id,occurred_at,contact_type,participants,subject,protocol_status")
        .eq("matter_id", matterId),
    ]);
    setAssets((a.data as Record<string, unknown>[] | null) ?? []);
    setFees((f.data as Record<string, unknown>[] | null) ?? []);
    setLogs((l.data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function add() {
    if (!matterId || !tenantId || !title) return;
    setWorking(true);
    const db = createClient();
    let operationError: string | null = null;
    if (kind === "asset")
      operationError =
        (
          await db
            .schema("court")
            .from("assets")
            .insert({
              tenant_id: tenantId,
              matter_id: matterId,
              asset_number: `AST-${Date.now()}`,
              asset_type: "other",
              description: title,
              estimated_value: Number(amount) || null,
            })
        ).error?.message ?? null;
    else if (kind === "fee")
      operationError =
        (
          await db
            .schema("court")
            .from("fees_expenses")
            .insert({
              tenant_id: tenantId,
              matter_id: matterId,
              professional_ref: "Current team",
              entry_date: new Date().toISOString().slice(0, 10),
              entry_type: "fee",
              description: title,
              amount: Number(amount) || 0,
            })
        ).error?.message ?? null;
    else
      operationError =
        (
          await db.schema("court").from("neutrality_log").insert({
            tenant_id: tenantId,
            matter_id: matterId,
            occurred_at: new Date().toISOString(),
            contact_type: "communication",
            subject: title,
            protocol_status: "compliant",
          })
        ).error?.message ?? null;
    setWorking(false);
    if (operationError) return addToast({ variant: "danger", message: operationError });
    setTitle("");
    setAmount("");
    addToast({ variant: "success", message: "Court-operation record preserved." });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Court and receivership operations</Heading>
        <Text onBackground="neutral-weak">
          Authority-bound contacts, neutrality log, asset inventory, fees, expenses, and court-ready
          records.
        </Text>
      </Column>
      <Card padding="20" border="neutral-alpha-medium" direction="column" gap="12">
        <Row gap="12" wrap>
          <Select
            id="court-record-kind"
            label="Record type"
            value={kind}
            onSelect={(v) => setKind(v as string)}
            options={[
              { value: "asset", label: "Receivership asset" },
              { value: "fee", label: "Fee or expense" },
              { value: "contact", label: "Neutrality/contact log" },
            ]}
          />
          <Input
            id="court-record-title"
            label="Description or subject"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          {kind !== "contact" && (
            <Input
              id="court-record-amount"
              label="Amount / estimated value"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          )}
          <Button onClick={add} loading={working} disabled={!title}>
            Record
          </Button>
        </Row>
      </Card>
      <Heading variant="heading-strong-s">Asset inventory</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "no", content: "Asset" },
            { key: "type", content: "Type" },
            { key: "description", content: "Description" },
            { key: "value", content: "Estimated value" },
            { key: "status", content: "Status" },
          ],
          rows: assets.map((a) => [
            String(a.asset_number),
            String(a.asset_type),
            String(a.description ?? "—"),
            String(a.estimated_value ?? "—"),
            String(a.status),
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Fee and expense review</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "date", content: "Date" },
            { key: "professional", content: "Professional" },
            { key: "type", content: "Type" },
            { key: "description", content: "Description" },
            { key: "amount", content: "Amount" },
            { key: "status", content: "Status" },
          ],
          rows: fees.map((f) => [
            String(f.entry_date),
            String(f.professional_ref),
            String(f.entry_type),
            String(f.description),
            String(f.amount),
            String(f.status),
          ]),
        }}
      />
      <Heading variant="heading-strong-s">Neutrality and contact log</Heading>
      <Table
        striped
        data={{
          headers: [
            { key: "at", content: "Occurred" },
            { key: "type", content: "Type" },
            { key: "participants", content: "Participants" },
            { key: "subject", content: "Subject" },
            { key: "protocol", content: "Protocol" },
          ],
          rows: logs.map((l) => [
            String(l.occurred_at),
            String(l.contact_type),
            String(l.participants ?? "—"),
            String(l.subject),
            String(l.protocol_status),
          ]),
        }}
      />
    </Column>
  );
}

export function JobMonitor() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [jobs, setJobs] = useState<Record<string, unknown>[]>([]);
  const [type, setType] = useState("ingestion");
  const [working, setWorking] = useState(false);
  const load = useCallback(async () => {
    if (!matterId) return;
    const { data } = await createClient()
      .schema("operations")
      .from("jobs")
      .select(
        "id,job_type,queue_name,status,attempt_count,max_attempts,created_at,started_at,finished_at,last_error",
      )
      .eq("matter_id", matterId)
      .order("created_at", { ascending: false })
      .limit(100);
    setJobs((data as Record<string, unknown>[] | null) ?? []);
  }, [matterId]);
  useEffect(() => {
    load();
  }, [load]);
  async function enqueue() {
    if (!matterId) return;
    setWorking(true);
    const { error } = await createClient()
      .schema("operations")
      .rpc("enqueue_job", {
        p_matter_id: matterId,
        p_job_type: type,
        p_payload: { requested_from: "job_monitor" },
        p_priority: 100,
      });
    setWorking(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    addToast({ variant: "success", message: "Durable job and queue message created." });
    load();
  }
  if (!matterId) return <Text onBackground="danger-weak">Set an active matter first.</Text>;
  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Background job operations</Heading>
        <Text onBackground="neutral-weak">
          Durable queue state for ingestion, hashing, OCR, analytics, alerts, rendering,
          notifications, and anchoring.
        </Text>
      </Column>
      <Row gap="12" vertical="end">
        <Select
          id="job-type"
          label="Job family"
          value={type}
          onSelect={(v) => setType(v as string)}
          options={[
            "ingestion",
            "hashing",
            "ocr",
            "analytics",
            "alerts",
            "report_compilation",
            "notifications",
            "anchoring",
          ].map((value) => ({ value, label: value.replaceAll("_", " ") }))}
        />
        <Button onClick={enqueue} loading={working}>
          Enqueue job
        </Button>
      </Row>
      <Table
        searchable
        striped
        data={{
          headers: [
            { key: "type", content: "Job" },
            { key: "queue", content: "Queue" },
            { key: "status", content: "Status" },
            { key: "attempts", content: "Attempts" },
            { key: "created", content: "Created" },
            { key: "error", content: "Last error" },
          ],
          rows: jobs.map((j) => [
            String(j.job_type),
            String(j.queue_name),
            String(j.status),
            `${String(j.attempt_count)}/${String(j.max_attempts)}`,
            String(j.created_at),
            String(j.last_error ?? "—"),
          ]),
        }}
        emptyState={<Text onBackground="neutral-weak">No jobs for this matter.</Text>}
      />
    </Column>
  );
}
