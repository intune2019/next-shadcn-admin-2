import { createHash, randomUUID } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

const MAX_FILE_BYTES = 50 * 1024 * 1024;

function safeName(value: string) {
  return (
    value
      .normalize("NFKC")
      .replace(/[^a-zA-Z0-9._-]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 160) || "document"
  );
}

export async function POST(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Authentication required." }, { status: 401 });

  const form = await request.formData();
  const file = form.get("file");
  const evidenceId = String(form.get("evidenceId") ?? "");
  const matterId = String(form.get("matterId") ?? "");
  if (!(file instanceof File) || !evidenceId || !matterId) {
    return Response.json(
      { error: "File, evidence item, and matter are required." },
      { status: 400 },
    );
  }
  if (file.size < 1 || file.size > MAX_FILE_BYTES) {
    return Response.json({ error: "Files must be between 1 byte and 50 MB." }, { status: 413 });
  }

  const { data: evidence, error: accessError } = await supabase
    .schema("evidence")
    .from("evidence_items")
    .select("id,tenant_id,matter_id")
    .eq("id", evidenceId)
    .eq("matter_id", matterId)
    .single();
  if (accessError || !evidence)
    return Response.json({ error: "Evidence item not found or access denied." }, { status: 403 });

  const bytes = Buffer.from(await file.arrayBuffer());
  const path = `${matterId}/${evidenceId}/${randomUUID()}-${safeName(file.name)}`;
  const admin = createAdminClient();
  const { data: fileRow, error: insertError } = await admin
    .schema("evidence")
    .from("evidence_files")
    .insert({
      tenant_id: evidence.tenant_id,
      matter_id: matterId,
      evidence_id: evidenceId,
      file_name: file.name,
      mime_type: file.type || "application/octet-stream",
      byte_size: file.size,
      storage_uri: path,
      created_by: user.id,
    })
    .select("id")
    .single();
  if (insertError || !fileRow) {
    return Response.json(
      { error: insertError?.message ?? "Could not register uploaded file." },
      { status: 500 },
    );
  }

  const digest = createHash("sha256").update(bytes).digest("hex");
  const { error: hashError } = await admin
    .schema("evidence")
    .from("evidence_hashes")
    .insert({
      tenant_id: evidence.tenant_id,
      matter_id: matterId,
      evidence_file_id: fileRow.id,
      algorithm: "sha256",
      hash_value: `\\x${digest}`,
      verification_result: "verified",
      created_by: user.id,
    });
  if (hashError) {
    await admin.schema("evidence").from("evidence_files").delete().eq("id", fileRow.id);
    return Response.json({ error: hashError.message }, { status: 500 });
  }
  const { error: uploadError } = await admin.storage.from("evidence").upload(path, bytes, {
    contentType: file.type || "application/octet-stream",
    upsert: false,
  });
  if (uploadError) {
    await admin
      .schema("evidence")
      .from("evidence_hashes")
      .delete()
      .eq("evidence_file_id", fileRow.id);
    await admin.schema("evidence").from("evidence_files").delete().eq("id", fileRow.id);
    return Response.json({ error: uploadError.message }, { status: 502 });
  }
  return Response.json({ id: fileRow.id, storageUri: path, sha256: digest }, { status: 201 });
}
