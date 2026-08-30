import { PatientCardView } from "../_components/patient-card-view";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return <PatientCardView patientId={id} view="back-office" />;
}
