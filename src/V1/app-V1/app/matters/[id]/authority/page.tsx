import { AuthorityScopeReview } from "@/components/matters/AuthorityScopeReview";

export default async function AuthorityScopePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AuthorityScopeReview matterId={id} />;
}
