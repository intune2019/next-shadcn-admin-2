import { notFound } from "next/navigation";
import { findResourceBySlug } from "@/lib/resources/config";
import { ResourceDetail } from "@/components/resource/ResourceDetail";

export default async function ResourceDetailPage({
  params,
}: {
  params: Promise<{ resource: string; id: string }>;
}) {
  const { resource, id } = await params;
  const config = findResourceBySlug(resource);
  if (!config) notFound();

  return <ResourceDetail config={config} id={id} />;
}
