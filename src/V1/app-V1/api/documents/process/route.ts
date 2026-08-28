import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { createClient } from "@/lib/supabase/server";

const execFile = promisify(execFileCallback);
const MAX_TEXT = 5_000_000;

function decodeXml(xml: string) {
  return xml
    .replace(/<w:tab\/?\s*>/g, "\t")
    .replace(/<w:br\/?\s*>/g, "\n")
    .replace(/<\/w:p>/g, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

async function extractText(filePath: string, mime: string, workDir: string) {
  const lower = filePath.toLowerCase();
  if (mime.startsWith("text/") || lower.endsWith(".txt") || lower.endsWith(".csv")) {
    return { text: await readFile(filePath, "utf8"), method: "native_text", pageCount: null };
  }
  if (mime === "application/pdf" || lower.endsWith(".pdf")) {
    const out = path.join(workDir, "document.txt");
    await execFile("/usr/bin/pdftotext", ["-layout", filePath, out], { maxBuffer: MAX_TEXT });
    let text = await readFile(out, "utf8");
    let method = "pdftotext";
    if (text.trim().length < 40) {
      const prefix = path.join(workDir, "page");
      await execFile("/usr/bin/pdftoppm", ["-png", "-r", "200", filePath, prefix], {
        maxBuffer: MAX_TEXT,
      });
      const images = (await readdir(workDir))
        .filter((name) => name.startsWith("page-") && name.endsWith(".png"))
        .sort();
      const pages: string[] = [];
      for (const image of images) {
        const { stdout } = await execFile(
          "/usr/bin/tesseract",
          [path.join(workDir, image), "stdout", "-l", "eng"],
          { maxBuffer: MAX_TEXT },
        );
        pages.push(stdout);
      }
      text = pages.join("\n\n");
      method = "tesseract_ocr";
    }
    const { stdout: info } = await execFile("/usr/bin/pdfinfo", [filePath], { maxBuffer: 100_000 });
    return { text, method, pageCount: Number(info.match(/^Pages:\s+(\d+)/m)?.[1] ?? 0) || null };
  }
  if (mime.includes("wordprocessingml") || lower.endsWith(".docx")) {
    const { stdout } = await execFile("/usr/bin/unzip", ["-p", filePath, "word/document.xml"], {
      maxBuffer: MAX_TEXT,
    });
    return { text: decodeXml(stdout), method: "docx_xml", pageCount: null };
  }
  if (mime === "application/msword" || lower.endsWith(".doc")) {
    const { stdout } = await execFile("/usr/bin/antiword", [filePath], { maxBuffer: MAX_TEXT });
    return { text: stdout, method: "antiword", pageCount: null };
  }
  throw new Error(`Unsupported document type: ${mime || path.extname(filePath)}`);
}

function entitiesFrom(text: string) {
  const patterns: [string, RegExp][] = [
    ["email", /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi],
    ["amount", /(?:USD\s*)?[$€£]\s?\d[\d,]*(?:\.\d{2})?/g],
    [
      "date",
      /\b(?:\d{1,2}[/-]){2}\d{2,4}\b|\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}\b/gi,
    ],
    [
      "account_reference",
      /\b(?:account|acct|invoice|wire|check)\s*(?:no\.?|number|#)?\s*[:#-]?\s*[A-Z0-9-]{4,}\b/gi,
    ],
  ];
  const found: {
    entity_type: string;
    entity_text: string;
    normalized_text: string;
    confidence: number;
    start_offset: number;
    end_offset: number;
  }[] = [];
  const seen = new Set<string>();
  for (const [entity_type, regex] of patterns) {
    for (const match of text.matchAll(regex)) {
      const normalized = match[0].toLowerCase().replace(/\s+/g, " ").trim();
      const key = `${entity_type}:${normalized}`;
      if (seen.has(key)) continue;
      seen.add(key);
      found.push({
        entity_type,
        entity_text: match[0],
        normalized_text: normalized,
        confidence: 0.9,
        start_offset: match.index ?? 0,
        end_offset: (match.index ?? 0) + match[0].length,
      });
      if (found.length >= 500) return found;
    }
  }
  return found;
}

export async function POST(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Authentication required." }, { status: 401 });
  const { evidenceFileId } = (await request.json()) as { evidenceFileId?: string };
  if (!evidenceFileId)
    return Response.json({ error: "evidenceFileId is required." }, { status: 400 });

  const { data: file, error: fileError } = await supabase
    .schema("evidence")
    .from("evidence_files")
    .select("id,tenant_id,matter_id,file_name,mime_type,storage_uri")
    .eq("id", evidenceFileId)
    .single();
  if (fileError || !file?.storage_uri)
    return Response.json({ error: "File not found or access denied." }, { status: 404 });
  const { data: job, error: jobError } = await supabase
    .schema("evidence")
    .from("document_processing_jobs")
    .insert({
      tenant_id: file.tenant_id,
      matter_id: file.matter_id,
      evidence_file_id: file.id,
      status: "processing",
      processor: "forensiq-native-v1",
      attempt_count: 1,
      started_at: new Date().toISOString(),
      created_by: user.id,
    })
    .select("id")
    .single();
  if (jobError || !job)
    return Response.json(
      { error: jobError?.message ?? "Could not create processing job." },
      { status: 500 },
    );

  const workDir = await mkdtemp(path.join(tmpdir(), "forensiq-doc-"));
  try {
    const { data: blob, error: downloadError } = await supabase.storage
      .from("evidence")
      .download(file.storage_uri);
    if (downloadError || !blob)
      throw new Error(downloadError?.message ?? "Storage download failed.");
    const inputPath = path.join(
      /* turbopackIgnore: true */ workDir,
      file.file_name?.replace(/[^a-zA-Z0-9._-]/g, "-") || "input.bin",
    );
    await writeFile(inputPath, Buffer.from(await blob.arrayBuffer()));
    const extracted = await extractText(inputPath, file.mime_type ?? "", workDir);
    const text = extracted.text.slice(0, MAX_TEXT);
    if (!text.trim()) throw new Error("No text could be extracted from the document.");
    const hash = createHash("sha256").update(text).digest("hex");
    const { data: document, error: documentError } = await supabase
      .schema("evidence")
      .from("extracted_documents")
      .insert({
        tenant_id: file.tenant_id,
        matter_id: file.matter_id,
        evidence_file_id: file.id,
        processing_job_id: job.id,
        extraction_method: extracted.method,
        content_text: text,
        page_count: extracted.pageCount,
        metadata: { character_count: text.length },
        content_sha256: `\\x${hash}`,
        created_by: user.id,
      })
      .select("id")
      .single();
    if (documentError || !document)
      throw new Error(documentError?.message ?? "Could not save extraction.");
    const entities = entitiesFrom(text).map((entity) => ({
      ...entity,
      tenant_id: file.tenant_id,
      matter_id: file.matter_id,
      extracted_document_id: document.id,
      created_by: user.id,
    }));
    if (entities.length) {
      const { error } = await supabase
        .schema("evidence")
        .from("extracted_entities")
        .insert(entities);
      if (error) throw new Error(error.message);
    }
    const { error: workingError } = await supabase.schema("evidence").rpc("save_working_copy", {
      p_evidence_file_id: file.id,
      p_content: text,
      p_change_note: `Initial ${extracted.method} extraction`,
    });
    if (workingError) throw new Error(workingError.message);
    await supabase
      .schema("evidence")
      .from("document_processing_jobs")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
        updated_by: user.id,
      })
      .eq("id", job.id);
    return Response.json({
      jobId: job.id,
      documentId: document.id,
      method: extracted.method,
      entityCount: entities.length,
      characterCount: text.length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Document processing failed.";
    await supabase
      .schema("evidence")
      .from("document_processing_jobs")
      .update({
        status: "failed",
        error_message: message.slice(0, 2000),
        completed_at: new Date().toISOString(),
        updated_by: user.id,
      })
      .eq("id", job.id);
    return Response.json({ error: message }, { status: 422 });
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}
