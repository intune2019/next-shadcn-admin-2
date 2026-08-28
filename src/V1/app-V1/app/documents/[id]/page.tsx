import { DocumentEditor } from "@/components/documents/DocumentEditor";

export default async function DocumentEditorPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <DocumentEditor id={id} />;
}
