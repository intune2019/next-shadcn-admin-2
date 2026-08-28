"use client";

import { createClient } from "@/lib/supabase/client";
import {
  Button,
  Column,
  Heading,
  Input,
  Line,
  Row,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
import { useCallback, useEffect, useState } from "react";

interface FileRecord {
  id: string;
  file_name: string | null;
  mime_type: string | null;
  storage_uri: string | null;
}
interface CopyRecord {
  id: string;
  version_number: number;
  content_text: string;
  change_note: string | null;
  created_at: string;
}

export function DocumentEditor({ id }: { id: string }) {
  const { addToast } = useToast();
  const [file, setFile] = useState<FileRecord | null>(null);
  const [copies, setCopies] = useState<CopyRecord[]>([]);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [content, setContent] = useState("");
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [processing, setProcessing] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    const { data: fileData, error } = await supabase
      .schema("evidence")
      .from("evidence_files")
      .select("id,file_name,mime_type,storage_uri")
      .eq("id", id)
      .single();
    if (error || !fileData) {
      addToast({ variant: "danger", message: error?.message ?? "Document not found." });
      setLoading(false);
      return;
    }
    setFile(fileData as FileRecord);
    if (fileData.storage_uri) {
      const { data } = await supabase.storage
        .from("evidence")
        .createSignedUrl(fileData.storage_uri, 900);
      setPreviewUrl(data?.signedUrl ?? null);
    }
    const { data: copyData } = await supabase
      .schema("evidence")
      .from("document_working_copies")
      .select("id,version_number,content_text,change_note,created_at")
      .eq("evidence_file_id", id)
      .order("version_number", { ascending: false });
    const loaded = (copyData as CopyRecord[] | null) ?? [];
    setCopies(loaded);
    setContent(loaded[0]?.content_text ?? "");
    setLoading(false);
  }, [addToast, id]);

  useEffect(() => {
    load();
  }, [load]);

  async function process() {
    setProcessing(true);
    const response = await fetch("/api/documents/process", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ evidenceFileId: id }),
    });
    const result = (await response.json()) as { error?: string; method?: string };
    setProcessing(false);
    if (!response.ok)
      return addToast({ variant: "danger", message: result.error ?? "Processing failed." });
    addToast({ variant: "success", message: `Extraction completed with ${result.method}.` });
    load();
  }

  async function save() {
    if (!content.trim()) return;
    setSaving(true);
    const supabase = createClient();
    const { error } = await supabase.schema("evidence").rpc("save_working_copy", {
      p_evidence_file_id: id,
      p_content: content,
      p_change_note: note || null,
    });
    setSaving(false);
    if (error) return addToast({ variant: "danger", message: error.message });
    setNote("");
    addToast({ variant: "success", message: "New immutable working-copy version saved." });
    load();
  }

  if (loading) return <Text onBackground="neutral-weak">Loading document…</Text>;
  if (!file) return <Text onBackground="danger-weak">Document unavailable.</Text>;
  return (
    <Column fillWidth gap="24">
      <Row fillWidth horizontal="between" vertical="center" wrap gap="12">
        <Column gap="4">
          <Heading variant="heading-strong-l">{file.file_name ?? "Document"}</Heading>
          <Text onBackground="neutral-weak">Original preview and versioned text workpaper</Text>
        </Column>
        <Button onClick={process} loading={processing} variant="secondary">
          Run extraction / OCR
        </Button>
      </Row>
      {previewUrl ? (
        <iframe
          title="Original document preview"
          src={previewUrl}
          style={{ width: "100%", minHeight: 520, border: "1px solid var(--neutral-alpha-medium)" }}
        />
      ) : (
        <Text onBackground="neutral-weak">A browser preview is not available for this file.</Text>
      )}
      <Line />
      <Column gap="12">
        <Heading variant="heading-strong-s">Editable working copy</Heading>
        <Textarea
          id="document-content"
          label="Extracted / edited text"
          value={content}
          lines={20}
          onChange={(event) => setContent(event.target.value)}
        />
        <Input
          id="change-note"
          label="Change note"
          value={note}
          onChange={(event) => setNote(event.target.value)}
        />
        <Row horizontal="end">
          <Button onClick={save} loading={saving} disabled={!content.trim()}>
            Save new version
          </Button>
        </Row>
      </Column>
      <Line />
      <Column gap="8">
        <Heading variant="heading-strong-s">Version history</Heading>
        {copies.length === 0 && (
          <Text onBackground="neutral-weak">
            No working-copy versions yet. Run extraction first.
          </Text>
        )}
        {copies.map((copy) => (
          <Row key={copy.id} fillWidth horizontal="between" gap="16">
            <Text>
              Version {copy.version_number} · {new Date(copy.created_at).toLocaleString()}
            </Text>
            <Text onBackground="neutral-weak">{copy.change_note ?? "No note"}</Text>
          </Row>
        ))}
      </Column>
    </Column>
  );
}
