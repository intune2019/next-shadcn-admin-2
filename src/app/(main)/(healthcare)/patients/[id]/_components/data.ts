export type PatientCardView = "front-desk" | "back-office" | "preventive";

export type PatientProfile = {
  id: string;
  mrn: string;
  name: string;
  initials: string;
  dob: string;
  age: number | null;
  sex: string;
  race: string;
  phone: string;
  email: string;
  emergencyContact: string;
  primaryProvider: string;
  careTeam: string;
  location: string;
  insurance: string;
  diagnosis: string;
};

const patientProfiles: Record<string, PatientProfile> = {
  "18425": {
    id: "18425",
    mrn: "MRN-18425",
    name: "Sarah Parker",
    initials: "SP",
    dob: "September 14, 1984",
    age: 41,
    sex: "Female",
    race: "White",
    phone: "(555) 014-2184",
    email: "sarah.parker@northstar.io",
    emergencyContact: "Michael Parker · (555) 014-2190",
    primaryProvider: "Dr. Priya Shah",
    careTeam: "Primary care",
    location: "Northside Clinic",
    insurance: "Blue Cross Blue Shield",
    diagnosis: "Type 2 diabetes mellitus",
  },
  "18424": {
    id: "18424",
    mrn: "MRN-18424",
    name: "Michael Brown",
    initials: "MB",
    dob: "January 22, 1972",
    age: 53,
    sex: "Male",
    race: "Black or African American",
    phone: "(555) 014-2192",
    email: "michael.brown@cedarpoint.co",
    emergencyContact: "Alicia Brown · (555) 014-2198",
    primaryProvider: "Dr. Elena Rossi",
    careTeam: "Cardiology",
    location: "Central Specialty Care",
    insurance: "Aetna",
    diagnosis: "Essential hypertension",
  },
  "18423": {
    id: "18423",
    mrn: "MRN-18423",
    name: "Linda Chen",
    initials: "LC",
    dob: "July 8, 1990",
    age: 35,
    sex: "Female",
    race: "Asian",
    phone: "(555) 014-2201",
    email: "linda.chen@brightpath.app",
    emergencyContact: "David Chen · (555) 014-2207",
    primaryProvider: "Dr. Marcus Reed",
    careTeam: "Behavioral health",
    location: "Eastside Rehabilitation",
    insurance: "UnitedHealthcare",
    diagnosis: "Generalized anxiety disorder",
  },
};

const defaultPatient: PatientProfile = {
  id: "",
  mrn: "",
  name: "Patient record",
  initials: "PR",
  dob: "Not on file",
  age: null,
  sex: "Not on file",
  race: "Not on file",
  phone: "Not on file",
  email: "Not on file",
  emergencyContact: "Not on file",
  primaryProvider: "Provider unassigned",
  careTeam: "Care team unassigned",
  location: "Location not on file",
  insurance: "Coverage not on file",
  diagnosis: "Diagnosis not on file",
};

export function getPatientProfile(patientId: string) {
  return patientProfiles[patientId] ?? { ...defaultPatient, id: patientId, mrn: `MRN-${patientId}` };
}
