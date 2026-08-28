"use client";

import { VeritasWidget } from "@/components/assistant/VeritasWidget";
import { createClient } from "@/lib/supabase/client";
import { TenantProvider, useTenant } from "@/lib/tenant/TenantContext";
import {
  Badge,
  Button,
  Card,
  Column,
  Heading,
  Input,
  Line,
  Row,
  Text,
  ToggleButton,
} from "@once-ui-system/core";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

interface MatterOption {
  id: string;
  tenant_id: string;
  matter_name: string;
  matter_number: string;
  status: string;
  matter_type: string;
  access_level?: string;
}
interface SearchResult {
  label: string;
  detail: string;
  href: string;
  kind: string;
}

function GlobalSearch() {
  const { matterId } = useTenant();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [working, setWorking] = useState(false);
  async function search() {
    if (query.trim().length < 2) return;
    setWorking(true);
    const db = createClient();
    const q = `%${query.trim().replace(/[,%()]/g, " ")}%`;
    const [m, e, n, f, r] = await Promise.all([
      db
        .schema("core")
        .from("matters")
        .select("id,matter_name,matter_number")
        .or(`matter_name.ilike.${q},matter_number.ilike.${q}`)
        .limit(5),
      db
        .schema("evidence")
        .from("evidence_items")
        .select("id,title,human_evidence_no")
        .eq("matter_id", matterId ?? "")
        .or(`title.ilike.${q},human_evidence_no.ilike.${q}`)
        .limit(5),
      db
        .schema("canonical")
        .from("entities")
        .select("id,name_normalized,entity_type")
        .eq("matter_id", matterId ?? "")
        .ilike("name_normalized", q)
        .limit(5),
      db
        .schema("investigation")
        .from("findings")
        .select("id,title,conclusion_status")
        .eq("matter_id", matterId ?? "")
        .ilike("title", q)
        .limit(5),
      db
        .schema("reporting")
        .from("reports")
        .select("id,title,status")
        .eq("matter_id", matterId ?? "")
        .ilike("title", q)
        .limit(5),
    ]);
    setResults([
      ...(m.data ?? []).map((x) => ({
        label: x.matter_name,
        detail: x.matter_number,
        href: `/app/matters/${x.id}`,
        kind: "Matter",
      })),
      ...(e.data ?? []).map((x) => ({
        label: x.title ?? x.human_evidence_no,
        detail: x.human_evidence_no,
        href: `/app/evidence-items/${x.id}`,
        kind: "Evidence",
      })),
      ...(n.data ?? []).map((x) => ({
        label: x.name_normalized ?? "Unnamed entity",
        detail: x.entity_type,
        href: `/app/entities/${x.id}`,
        kind: "Entity",
      })),
      ...(f.data ?? []).map((x) => ({
        label: x.title,
        detail: x.conclusion_status,
        href: `/app/findings/${x.id}`,
        kind: "Finding",
      })),
      ...(r.data ?? []).map((x) => ({
        label: x.title,
        detail: x.status,
        href: `/app/reports/${x.id}`,
        kind: "Report",
      })),
    ]);
    setWorking(false);
  }
  return (
    <Column gap="4" style={{ position: "relative", minWidth: 280 }}>
      <Row gap="4">
        <Input
          id="global-search"
          label="Search this matter"
          height="s"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              search();
            }
          }}
        />
        <Button size="s" variant="secondary" onClick={search} loading={working}>
          Search
        </Button>
      </Row>
      {results.length > 0 && (
        <Card
          padding="8"
          border="neutral-alpha-medium"
          direction="column"
          gap="2"
          style={{
            position: "absolute",
            top: "58px",
            left: 0,
            right: 0,
            zIndex: 50,
            maxHeight: 320,
            overflowY: "auto",
          }}
        >
          {results.map((result, index) => (
            <ToggleButton
              key={`${result.kind}-${index}`}
              href={result.href}
              fillWidth
              horizontal="start"
              size="s"
            >
              <Column gap="0">
                <Text variant="label-default-s">{result.label}</Text>
                <Text variant="body-default-xs" onBackground="neutral-weak">
                  {result.kind} · {result.detail}
                </Text>
              </Column>
            </ToggleButton>
          ))}
          <Button size="s" variant="tertiary" onClick={() => setResults([])}>
            Close
          </Button>
        </Card>
      )}
    </Column>
  );
}

function WorkspaceHeader() {
  const router = useRouter();
  const { tenantId, matterId, setTenantId, setMatterId } = useTenant();
  const [matters, setMatters] = useState<MatterOption[]>([]);
  const [tenantName, setTenantName] = useState("Forens_iQ");
  const [role, setRole] = useState("Practitioner");
  const [openItems, setOpenItems] = useState(0);
  const load = useCallback(async () => {
    const db = createClient();
    const {
      data: { user },
    } = await db.auth.getUser();
    const { data: matterRows } = await db
      .schema("core")
      .from("matters")
      .select("id,tenant_id,matter_name,matter_number,status,matter_type")
      .order("matter_name");
    const options = (matterRows as MatterOption[] | null) ?? [];
    setMatters(options);
    const active = options.find((m) => m.id === matterId) ?? options[0];
    if (active && !matterId) {
      setMatterId(active.id);
      setTenantId(active.tenant_id);
    }
    if (active) {
      const [{ data: t }, { data: a }, { count: alerts }, { count: deadlines }] = await Promise.all(
        [
          db
            .schema("core")
            .from("tenants")
            .select("tenant_name")
            .eq("id", active.tenant_id)
            .maybeSingle(),
          db
            .schema("core")
            .from("matter_access")
            .select("access_level")
            .eq("matter_id", active.id)
            .eq("user_id", user?.id ?? "")
            .maybeSingle(),
          db
            .schema("investigation")
            .from("alerts")
            .select("id", { count: "exact", head: true })
            .eq("matter_id", active.id)
            .neq("review_status", "closed"),
          db
            .schema("core")
            .from("deadlines")
            .select("id", { count: "exact", head: true })
            .eq("matter_id", active.id)
            .eq("completed", false),
        ],
      );
      setTenantName(t?.tenant_name ?? "Forens_iQ");
      setRole((a?.access_level ?? "practitioner").replaceAll("_", " "));
      setOpenItems((alerts ?? 0) + (deadlines ?? 0));
    }
  }, [matterId, setMatterId, setTenantId]);
  useEffect(() => {
    load();
  }, [load]);
  const active = matters.find((m) => m.id === matterId);
  return (
    <>
      <Row
        fillWidth
        horizontal="between"
        vertical="center"
        paddingX="24"
        paddingY="12"
        gap="16"
        wrap
      >
        <Row gap="16" vertical="center">
          <Heading variant="heading-strong-m">Forens_iQ</Heading>
          <Text onBackground="neutral-weak">{tenantName}</Text>
        </Row>
        <Row gap="12" vertical="end" wrap>
          <Column gap="2">
            <Text variant="label-default-xs" onBackground="neutral-weak">
              Current matter
            </Text>
            <select
              aria-label="Current matter"
              value={matterId ?? ""}
              onChange={(e) => {
                const next = matters.find((m) => m.id === e.target.value);
                setMatterId(next?.id ?? null);
                setTenantId(next?.tenant_id ?? null);
                if (next) router.push(`/app/matters/${next.id}`);
              }}
              style={{
                background: "var(--surface-background)",
                color: "inherit",
                border: "1px solid var(--neutral-alpha-medium)",
                borderRadius: 8,
                padding: "9px 12px",
                minWidth: 250,
              }}
            >
              {matters.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.matter_name} · {m.matter_number}
                </option>
              ))}
            </select>
          </Column>
          {active && (
            <Badge onBackground={active.status === "active" ? "success-strong" : "warning-strong"}>
              {active.status}
            </Badge>
          )}
          <Badge onBackground="neutral-weak">{role}</Badge>
          <Badge onBackground={openItems ? "warning-strong" : "neutral-weak"}>
            {openItems} open items
          </Badge>
          <GlobalSearch />
          <Button
            size="s"
            variant="tertiary"
            onClick={async () => {
              await createClient().auth.signOut();
              router.push("/sign-in");
              router.refresh();
            }}
          >
            Profile / Sign out
          </Button>
        </Row>
      </Row>
      <Line />
    </>
  );
}

const MODULES = [
  ["Portfolio", "/app"],
  ["Fraud", "/app/fraud"],
  ["Treasury", "/app/treasury"],
  ["GRC", "/app/grc"],
  ["Special Services", "/app/special-services"],
] as const;
const MODULE_LINKS = {
  fraud: [
    ["Dashboard", "fraud"],
    ["Allegations", "allegations"],
    ["Evidence", "documents"],
    ["People & Entities", "entities"],
    ["Financial Activity", "transactions"],
    ["Alerts & Leads", "alerts"],
    ["Interviews", "interviews"],
    ["Workpapers", "workpapers"],
    ["Findings", "findings"],
    ["Analytics", "rule-runner"],
    ["Funds Flow", "financial-analysis"],
    ["Calculations", "calculations"],
    ["Timeline", "timeline"],
  ],
  treasury: [["Dashboard & Review", "treasury"]],
  grc: [["Dashboard & Review", "grc"]],
  special: [
    ["Dashboard", "special-services"],
    ["Court Authority", "appointments"],
    ["Court Obligations", "appointment-obligations"],
    ["Court Operations", "court-operations"],
    ["Claims", "claims"],
    ["Claim Decisions", "claim-determinations"],
    ["Distributions", "claim-distributions"],
  ],
} as const;

function ModuleTabs() {
  const pathname = usePathname();
  const active =
    pathname === "/app"
      ? "/app"
      : pathname.startsWith("/app/treasury")
        ? "/app/treasury"
        : pathname.startsWith("/app/grc")
          ? "/app/grc"
          : pathname.startsWith("/app/special-services") ||
              pathname.startsWith("/app/court") ||
              pathname.startsWith("/app/appointment") ||
              pathname.startsWith("/app/claims") ||
              pathname.startsWith("/app/claim-")
            ? "/app/special-services"
            : "/app/fraud";
  return (
    <Row
      fillWidth
      gap="8"
      paddingX="24"
      paddingY="8"
      wrap
      style={{ borderBottom: "1px solid var(--neutral-alpha-medium)" }}
    >
      {MODULES.map(([label, href]) => (
        <ToggleButton key={href} href={href} selected={active === href} size="s">
          {label}
        </ToggleButton>
      ))}
    </Row>
  );
}

function MatterNav() {
  const pathname = usePathname();
  const { matterId } = useTenant();
  const [admin, setAdmin] = useState(false);
  const [canAdmin, setCanAdmin] = useState(false);
  useEffect(() => {
    async function check() {
      if (!matterId) return;
      const db = createClient();
      const {
        data: { user },
      } = await db.auth.getUser();
      const { data } = await db
        .schema("core")
        .from("matter_access")
        .select("access_level")
        .eq("matter_id", matterId)
        .eq("user_id", user?.id ?? "")
        .maybeSingle();
      setCanAdmin(data?.access_level === "matter_admin");
    }
    check();
  }, [matterId]);
  const moduleKey = pathname.startsWith("/app/treasury")
    ? "treasury"
    : pathname.startsWith("/app/grc")
      ? "grc"
      : pathname.startsWith("/app/special-services") ||
          pathname.startsWith("/app/court") ||
          pathname.startsWith("/app/appointment") ||
          pathname.startsWith("/app/claims") ||
          pathname.startsWith("/app/claim-")
        ? "special"
        : "fraud";
  const moduleLabel =
    moduleKey === "special"
      ? "Special Services"
      : moduleKey === "grc"
        ? "GRC"
        : moduleKey[0].toUpperCase() + moduleKey.slice(1);
  return (
    <Column gap="20" minWidth={13} paddingRight="16">
      <Column gap="8">
        <Text variant="label-default-s" onBackground="neutral-weak">
          {moduleLabel}
        </Text>
        {MODULE_LINKS[moduleKey].map(([label, slug]) => {
          const href = `/app/${slug}`;
          return (
            <ToggleButton
              key={slug}
              href={href}
              selected={pathname === href || pathname.startsWith(`${href}/`)}
              fillWidth
              horizontal="start"
              size="s"
            >
              {label}
            </ToggleButton>
          );
        })}
        <Text variant="label-default-xs" onBackground="neutral-weak" marginTop="8">
          Matter management
        </Text>
        {matterId && (
          <ToggleButton
            href={`/app/matters/${matterId}`}
            selected={pathname === `/app/matters/${matterId}`}
            fillWidth
            horizontal="start"
            size="s"
          >
            Matter overview
          </ToggleButton>
        )}
        <ToggleButton
          href="/app/tasks"
          selected={pathname === "/app/tasks"}
          fillWidth
          horizontal="start"
          size="s"
        >
          Tasks & deadlines
        </ToggleButton>
        {matterId && (
          <ToggleButton
            href={`/app/matters/${matterId}/authority`}
            selected={pathname.includes("/authority")}
            fillWidth
            horizontal="start"
            size="s"
          >
            Authority & access
          </ToggleButton>
        )}
      </Column>
      {canAdmin && (
        <>
          <Line />
          <Button size="s" variant="tertiary" onClick={() => setAdmin(!admin)}>
            {admin ? "Hide administration" : "Platform administration"}
          </Button>
          {admin && (
            <Column gap="4">
              <Text variant="label-default-xs" onBackground="neutral-weak">
                Data operations
              </Text>
              <ToggleButton href="/app/data-ingestion" fillWidth horizontal="start" size="s">
                Data readiness
              </ToggleButton>
              <ToggleButton href="/app/mappings" fillWidth horizontal="start" size="s">
                Mapping library
              </ToggleButton>
              <ToggleButton
                href="/app/entity-match-candidates"
                fillWidth
                horizontal="start"
                size="s"
              >
                Match review
              </ToggleButton>
              <ToggleButton href="/app/job-monitor" fillWidth horizontal="start" size="s">
                System jobs
              </ToggleButton>
              <ToggleButton href="/app/audit-events" fillWidth horizontal="start" size="s">
                Audit log
              </ToggleButton>
            </Column>
          )}
        </>
      )}
    </Column>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  return (
    <TenantProvider>
      <Column fillWidth minHeight="100vh">
        <WorkspaceHeader />
        <ModuleTabs />
        <Row fillWidth flex={1} paddingX="24" paddingY="24" gap="24">
          {pathname !== "/app" && <MatterNav />}
          <Column
            flex={1}
            paddingLeft={pathname === "/app" ? "0" : "24"}
            style={
              pathname === "/app"
                ? undefined
                : { borderLeft: "1px solid var(--neutral-alpha-medium)" }
            }
          >
            {children}
          </Column>
        </Row>
      </Column>
      <VeritasWidget />
    </TenantProvider>
  );
}
