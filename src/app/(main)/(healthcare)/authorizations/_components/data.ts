export const authorizationStatuses = ["Draft", "Submitted", "Pending", "Approved", "Denied", "Expired"] as const;

export type AuthorizationStatus = (typeof authorizationStatuses)[number];

export type AuthorizationPriority = "Routine" | "Urgent";

export type Authorization = {
  id: string;
  patient: string;
  patientInitials: string;
  mrn: string;
  payer: string;
  provider: string;
  service: string;
  requestedUnits: number;
  approvedUnits?: number;
  status: AuthorizationStatus;
  priority: AuthorizationPriority;
  submittedOn: string;
  decisionDue: string;
  referralId: string;
  documents: number;
  location: string;
  expiresInDays?: number;
  updatedBy: string;
  updatedAt: string;
};

export const authorizations: Authorization[] = [
  {
    id: "PA-2025-04821",
    patient: "Ava Martinez",
    patientInitials: "AM",
    mrn: "MRN-104928",
    payer: "Blue Cross Blue Shield",
    provider: "Dr. Priya Shah",
    service: "MRI lumbar spine without contrast",
    requestedUnits: 1,
    status: "Pending",
    priority: "Urgent",
    submittedOn: "May 12, 2025",
    decisionDue: "Today, 4:00 PM",
    referralId: "REF-14290",
    documents: 4,
    location: "Northside Clinic",
    updatedBy: "M. Chen, Referral coordinator",
    updatedAt: "28 minutes ago",
  },
  {
    id: "PA-2025-04818",
    patient: "Noah Williams",
    patientInitials: "NW",
    mrn: "MRN-107341",
    payer: "Aetna",
    provider: "Dr. James Kim",
    service: "Physical therapy evaluation and treatment",
    requestedUnits: 12,
    status: "Submitted",
    priority: "Routine",
    submittedOn: "May 12, 2025",
    decisionDue: "May 16, 2025",
    referralId: "REF-14284",
    documents: 3,
    location: "Eastside Rehabilitation",
    updatedBy: "R. Patel, Medical assistant",
    updatedAt: "1 hour ago",
  },
  {
    id: "PA-2025-04812",
    patient: "Sophia Johnson",
    patientInitials: "SJ",
    mrn: "MRN-102775",
    payer: "UnitedHealthcare",
    provider: "Dr. Elena Rossi",
    service: "Cardiology consultation",
    requestedUnits: 1,
    approvedUnits: 1,
    status: "Approved",
    priority: "Routine",
    submittedOn: "May 8, 2025",
    decisionDue: "Decision received",
    referralId: "REF-14268",
    documents: 5,
    location: "Central Specialty Care",
    expiresInDays: 12,
    updatedBy: "A. Thompson, Authorization coordinator",
    updatedAt: "Yesterday",
  },
  {
    id: "PA-2025-04804",
    patient: "Liam Brown",
    patientInitials: "LB",
    mrn: "MRN-109056",
    payer: "Cigna",
    provider: "Dr. Marcus Reed",
    service: "Sleep study, attended polysomnography",
    requestedUnits: 1,
    status: "Denied",
    priority: "Routine",
    submittedOn: "May 7, 2025",
    decisionDue: "Decision received",
    referralId: "REF-14251",
    documents: 2,
    location: "Westside Primary Care",
    updatedBy: "S. Green, Referral coordinator",
    updatedAt: "Yesterday",
  },
  {
    id: "PA-2025-04796",
    patient: "Mia Davis",
    patientInitials: "MD",
    mrn: "MRN-103882",
    payer: "Medicare",
    provider: "Dr. Priya Shah",
    service: "Home health skilled nursing visits",
    requestedUnits: 8,
    status: "Draft",
    priority: "Routine",
    submittedOn: "Not submitted",
    decisionDue: "Ready for submission",
    referralId: "REF-14237",
    documents: 1,
    location: "Northside Clinic",
    updatedBy: "J. Nelson, Medical assistant",
    updatedAt: "2 hours ago",
  },
  {
    id: "PA-2025-04788",
    patient: "Ethan Garcia",
    patientInitials: "EG",
    mrn: "MRN-106511",
    payer: "Blue Cross Blue Shield",
    provider: "Dr. James Kim",
    service: "CT chest with contrast",
    requestedUnits: 1,
    status: "Expired",
    priority: "Urgent",
    submittedOn: "Apr 14, 2025",
    decisionDue: "Expired May 10, 2025",
    referralId: "REF-14219",
    documents: 4,
    location: "Downtown Imaging",
    updatedBy: "T. Brooks, Authorization coordinator",
    updatedAt: "3 days ago",
  },
];
