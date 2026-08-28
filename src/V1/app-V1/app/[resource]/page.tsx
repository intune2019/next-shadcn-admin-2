import { notFound } from "next/navigation";
import { findResourceBySlug, allResources } from "@/lib/resources/config";
import { ResourceList } from "@/components/resource/ResourceList";

export function generateStaticParams() {
  return allResources.map((r) => ({ resource: r.slug }));
}

export default async function ResourcePage({
  params,
}: {
  params: Promise<{ resource: string }>;
}) {
  const { resource } = await params;
  const config = findResourceBySlug(resource);
  if (!config) notFound();

  return <ResourceList config={config} />;
}
