import {
  Banknote,
  Calendar,
  ChartBar,
  FolderOpen,
  Gauge,
  HeartPulse,
  LayoutDashboard,
  ListTodo,
  Lock,
  MessageSquare,
  ReceiptText,
  UserRound,
  Users,
  type LucideIcon,
} from "lucide-react";

export type NavBadge = "new" | "soon";

export interface NavSubItem {
  id: string;
  title: string;
  url: string;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

interface NavItemBase {
  id: string;
  title: string;
  icon?: LucideIcon;
  badge?: NavBadge;
  disabled?: boolean;
  newTab?: boolean;
}

export interface NavMainLinkItem extends NavItemBase {
  url: string;
  subItems?: never;
}

export interface NavMainParentItem extends NavItemBase {
  subItems: NavSubItem[];
}

export type NavMainItem = NavMainLinkItem | NavMainParentItem;

export interface NavGroup {
  id: number;
  label?: string;
  items: NavMainItem[];
}

export const sidebarItems: NavGroup[] = [
  {
    id: 1,
    label: "Workspace",
    items: [
      {
        id: "command-center",
        title: "Command center",
        url: "/dashboard",
        icon: LayoutDashboard,
      },
      {
        id: "patients",
        title: "Patients",
        url: "/patients",
        icon: Users,
      },
      {
        id: "scheduling",
        title: "Scheduling",
        url: "/scheduling",
        icon: Calendar,
      },
    ],
  },
  {
    id: 2,
    label: "Clinical",
    items: [
      {
        id: "providers",
        title: "Providers",
        url: "/providers",
        icon: UserRound,
      },
      {
        id: "encounters",
        title: "Encounters",
        url: "/encounters",
        icon: HeartPulse,
      },
      {
        id: "live-care",
        title: "Live care",
        url: "/dashboard/patient-monitoring",
        icon: HeartPulse,
      },
      {
        id: "referrals",
        title: "Referrals",
        url: "/referrals",
        icon: MessageSquare,
      },
      {
        id: "authorizations",
        title: "Authorizations",
        url: "/authorizations",
        icon: Lock,
      },
    ],
  },
  {
    id: 3,
    label: "Revenue & operations",
    items: [
      {
        id: "billing",
        title: "Billing",
        url: "/billing",
        icon: Banknote,
      },
      {
        id: "documents",
        title: "Documents",
        url: "/dashboard/file-manager",
        icon: FolderOpen,
      },
      {
        id: "claims",
        title: "Claims",
        url: "/dashboard/invoice",
        icon: ReceiptText,
      },
      {
        id: "reporting",
        title: "Reporting",
        url: "/dashboard/reporting",
        icon: ChartBar,
      },
    ],
  },
  {
    id: 4,
    label: "Administration",
    items: [
      {
        id: "team",
        title: "Team & access",
        url: "/dashboard/users",
        icon: Users,
      },
      {
        id: "roles",
        title: "Roles & permissions",
        url: "/dashboard/roles",
        icon: Lock,
      },
      {
        id: "practice-settings",
        title: "Practice settings",
        url: "/dashboard/profile",
        icon: ListTodo,
      },
      {
        id: "compliance",
        title: "Compliance",
        url: "/dashboard/analytics",
        icon: Gauge,
      },
    ],
  },
];
