import { MatterDashboard } from "@/components/dashboard/MatterDashboard";

export default async function MatterDashboardPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <MatterDashboard matterId={id} />;
}
