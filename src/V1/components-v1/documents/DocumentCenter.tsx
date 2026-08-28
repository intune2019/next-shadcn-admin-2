"use client";

import { RelationSelect } from "@/components/resource/RelationSelect";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";
import { Button, Column, Heading, Line, Row, Table, Text, useToast } from "@once-ui-system/core";
import { useCallback, useEffect, useRef, useState } from "react";

interface FileRow {
  id: string;
  file_name: string | null;
  mime_type: string | null;
  byte_size: number | null;
  storage_uri: string | null;
  evidence_id: string;
  created_at: string;
}

function formatBytes(n: number | null): string {
  if (!n) return "—";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export function DocumentCenter() {
  const { matterId } = useTenant();
  const { addToast } = useToast();
  const [files, setFiles] = useState<FileRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [evidenceId, setEvidenceId] = useState("");
  const [uploading, setUploading] = useState(false);
  const [processingId, setProcessingId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    if (!matterId) {
      setFiles([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const supabase = createClient();
    const { data } = await supabase
      .schema("evidence")
      .from("evidence_files")
      .select("id, file_name, mime_type, byte_size, storage_uri, evidence_id, created_at")
      .eq("matter_id", matterId)
      .order("created_at", { ascending: false });
    setFiles((data as FileRow[]) ?? []);
    setLoading(false);
  }, [matterId]);

  useEffect(() => {
    load();
  }, [load]);

  async function handleUpload() {
    const file = fileInputRef.current?.files?.[0];
    if (!file || !evidenceId || !matterId) return;
    setUploading(true);
    const body = new FormData();
    body.set("file", file);
    body.set("evidenceId", evidenceId);
    body.set("matterId", matterId);
    const response = await fetch("/api/documents/upload", { method: "POST", body });
    const result = (await response.json()) as { error?: string };
    setUploading(false);
    if (!response.ok) {
      addToast({ variant: "danger", message: result.error ?? "Upload failed." });
      return;
    }
    addToast({ variant: "success", message: "File uploaded." });
    if (fileInputRef.current) fileInputRef.current.value = "";
    load();
  }

  async function handleProcess(id: string) {
    setProcessingId(id);
    const response = await fetch("/api/documents/process", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ evidenceFileId: id }),
    });
    const result = (await response.json()) as { error?: string; entityCount?: number };
    setProcessingId(null);
    if (!response.ok) {
      addToast({ variant: "danger", message: result.error ?? "Processing failed." });
      return;
    }
    addToast({
      variant: "success",
      message: `Document processed; ${result.entityCount ?? 0} entities extracted.`,
    });
  }

  async function handlePreview(storageUri: string | null) {
    if (!storageUri) return;
    const supabase = createClient();
    const { data, error } = await supabase.storage.from("evidence").createSignedUrl(storageUri, 60);
    if (error || !data) {
      addToast({ variant: "danger", message: error?.message ?? "Could not create preview link." });
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  const headers = [
    { content: "File", key: "file_name" },
    { content: "Type", key: "mime_type" },
    { content: "Size", key: "byte_size" },
    { content: "Uploaded", key: "created_at" },
    { content: "", key: "actions" },
  ];
  const rows = files.map((f) => [
    f.file_name ?? "—",
    f.mime_type ?? "—",
    formatBytes(f.byte_size),
    new Date(f.created_at).toLocaleString(),
    <Row key={f.id} gap="4" wrap>
      <Button size="s" variant="secondary" onClick={() => handlePreview(f.storage_uri)}>
        Preview
      </Button>
      <Button
        size="s"
        variant="secondary"
        loading={processingId === f.id}
        onClick={() => handleProcess(f.id)}
      >
        Extract
      </Button>
      <Button size="s" variant="tertiary" href={`/app/documents/${f.id}`}>
        Edit text
      </Button>
    </Row>,
  ]);

  return (
    <Column fillWidth gap="24">
      <Column gap="4">
        <Heading variant="heading-strong-l">Document center</Heading>
        <Text onBackground="neutral-weak">
          Uploads are preserved with SHA-256, can be previewed, OCR/text-extracted, and edited as
          versioned working copies.
        </Text>
      </Column>

      {!matterId && (
        <Text onBackground="danger-weak">
          Set an active matter (top bar) to see or upload documents.
        </Text>
      )}

      {matterId && (
        <>
          <Row gap="8" vertical="end" wrap fillWidth>
            <RelationSelect
              id="doc-evidence"
              label="Attach to evidence item"
              relation={{
                schema: "evidence",
                table: "evidence_items",
                labelKey: "human_evidence_no",
                valueKey: "id",
                matterScoped: true,
              }}
              value={evidenceId}
              onSelect={setEvidenceId}
            />
            <input
              ref={fileInputRef}
              type="file"
              style={{ color: "var(--neutral-on-background-weak)" }}
            />
            <Button
              onClick={handleUpload}
              loading={uploading}
              disabled={!evidenceId}
              data-border="sharp"
            >
              Upload
            </Button>
          </Row>
          <Line />
          <Table
            data={{ headers, rows }}
            loading={loading}
            emptyState={<Text onBackground="neutral-weak">No documents uploaded yet.</Text>}
            searchable
            striped
          />
        </>
      )}
    </Column>
  );
}
