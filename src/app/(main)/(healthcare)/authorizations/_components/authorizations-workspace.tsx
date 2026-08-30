"use client";

import * as React from "react";
import { CheckCircle2, CircleAlert, Clock3, FileText, Plus, Search, ShieldCheck } from "lucide-react";

import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

import { AuthorizationCard } from "./authorization-card";
import { authorizationStatuses, type Authorization, type AuthorizationStatus } from "./data";

type AuthorizationView = "all" | "review" | "decisions";

const statusOptions = ["All statuses", ...authorizationStatuses] as const;
const payerOptions = ["All payers", "Aetna", "Blue Cross Blue Shield", "Cigna", "Medicare", "UnitedHealthcare"] as const;

function getNextAction(status: AuthorizationStatus) {
  if (status === "Draft") return { label: "Submit request", status: "Submitted" as const };
  if (status === "Submitted") return { label: "Start review", status: "Pending" as const };
  if (status === "Pending") return { label: "Approve request", status: "Approved" as const };
  return null;
}

export function AuthorizationsWorkspace({ authorizations }: { authorizations: Authorization[] }) {
  const [authorizationRows, setAuthorizationRows] = React.useState(authorizations);
  const [activeView, setActiveView] = React.useState<AuthorizationView>("all");
  const [search, setSearch] = React.useState("");
  const [statusFilter, setStatusFilter] = React.useState<(typeof statusOptions)[number]>("All statuses");
  const [payerFilter, setPayerFilter] = React.useState<(typeof payerOptions)[number]>("All payers");
  const [selectedAuthorizationId, setSelectedAuthorizationId] = React.useState(authorizations[0]?.id ?? "");

  const filteredAuthorizations = React.useMemo(
    () =>
      authorizationRows.filter((authorization) => {
        const matchesView =
          activeView === "all" ||
          (activeView === "review" && ["Submitted", "Pending"].includes(authorization.status)) ||
          (activeView === "decisions" && ["Approved", "Denied", "Expired"].includes(authorization.status));
        const matchesStatus = statusFilter === "All statuses" || authorization.status === statusFilter;
        const matchesPayer = payerFilter === "All payers" || authorization.payer === payerFilter;
        const normalizedSearch = search.toLowerCase();
        const matchesSearch = [
          authorization.patient,
          authorization.id,
          authorization.mrn,
          authorization.provider,
          authorization.service,
        ].some((value) => value.toLowerCase().includes(normalizedSearch));

        return matchesView && matchesStatus && matchesPayer && matchesSearch;
      }),
    [activeView, authorizationRows, payerFilter, search, statusFilter],
  );

  const selectedAuthorization = authorizationRows.find(
    (authorization) => authorization.id === selectedAuthorizationId,
  );
  const nextAction = selectedAuthorization ? getNextAction(selectedAuthorization.status) : null;
  const pendingCount = authorizationRows.filter((authorization) => authorization.status === "Pending").length;
  const submittedCount = authorizationRows.filter((authorization) => authorization.status === "Submitted").length;
  const approvedCount = authorizationRows.filter((authorization) => authorization.status === "Approved").length;
  const expiringCount = authorizationRows.filter(
    (authorization) => authorization.expiresInDays !== undefined && authorization.expiresInDays <= 14,
  ).length;
  const reviewQueue = authorizationRows.filter((authorization) => ["Submitted", "Pending"].includes(authorization.status));

  function updateAuthorizationStatus(authorizationId: string, status: AuthorizationStatus) {
    setAuthorizationRows((currentRows) =>
      currentRows.map((authorization) =>
        authorization.id === authorizationId
          ? {
              ...authorization,
              status,
              decisionDue: status === "Approved" ? "Decision received" : authorization.decisionDue,
              approvedUnits: status === "Approved" ? authorization.requestedUnits : authorization.approvedUnits,
              updatedAt: "Just now",
              updatedBy: "Arham Khan, Authorization manager",
            }
          : authorization,
      ),
    );
  }

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex flex-col items-start gap-4 sm:flex-row sm:justify-between">
        <div className="flex flex-col gap-1">
          <h1 className="text-3xl tracking-tight">Prior authorizations</h1>
          <p className="text-muted-foreground text-sm">
            Coordinate payer decisions, clinical documentation, and referral readiness across your practice.
          </p>
        </div>
        <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto">
          <Button size="sm" variant="outline">
            <FileText data-icon="inline-start" />
            Documentation queue
          </Button>
          <Button size="sm">
            <Plus data-icon="inline-start" />
            New authorization
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <Card size="sm">
          <CardHeader>
            <CardTitle className="sr-only">Pending payer decisions</CardTitle>
            <CardDescription>Pending payer decisions</CardDescription>
            <CardAction>
              <Clock3 className="size-4 text-muted-foreground" />
            </CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-3xl leading-none tracking-tight">{pendingCount}</p>
            <p className="mt-2 text-muted-foreground text-sm">{submittedCount} additional requests are submitted.</p>
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader>
            <CardTitle className="sr-only">Approvals this week</CardTitle>
            <CardDescription>Approvals this week</CardDescription>
            <CardAction>
              <CheckCircle2 className="size-4 text-muted-foreground" />
            </CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-3xl leading-none tracking-tight">{approvedCount}</p>
            <p className="mt-2 text-muted-foreground text-sm">Decisions with complete supporting records.</p>
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader>
            <CardTitle className="sr-only">Expiring in 14 days</CardTitle>
            <CardDescription>Expiring in 14 days</CardDescription>
            <CardAction>
              <CircleAlert className="size-4 text-muted-foreground" />
            </CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-3xl leading-none tracking-tight">{expiringCount}</p>
            <p className="mt-2 text-muted-foreground text-sm">Coordinate treatment before coverage ends.</p>
          </CardContent>
        </Card>
        <Card size="sm">
          <CardHeader>
            <CardTitle className="sr-only">Referral linked</CardTitle>
            <CardDescription>Referral linked</CardDescription>
            <CardAction>
              <ShieldCheck className="size-4 text-muted-foreground" />
            </CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-3xl leading-none tracking-tight">{authorizationRows.length}</p>
            <p className="mt-2 text-muted-foreground text-sm">Active authorizations retain clinical context.</p>
          </CardContent>
        </Card>
      </div>

      <Alert>
        <CircleAlert />
        <AlertTitle>Documentation needs attention</AlertTitle>
        <AlertDescription>
          One request is approaching its payer decision deadline without all ordered clinical records attached.
        </AlertDescription>
        <AlertAction>
          <Button size="sm" variant="link" onClick={() => setActiveView("review")}>
            Review queue
          </Button>
        </AlertAction>
      </Alert>

      <div className="grid min-h-0 grid-cols-1 gap-4 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader className="border-b has-data-[slot=card-action]:grid-cols-1 md:has-data-[slot=card-action]:grid-cols-[1fr_auto]">
            <CardTitle>Authorization workspace</CardTitle>
            <CardDescription>Review requests by payer status, patient context, and referral readiness.</CardDescription>
            <CardAction className="col-start-1 row-start-auto flex w-full flex-wrap gap-2 justify-self-stretch md:col-start-2 md:row-span-2 md:row-start-1 md:w-auto md:justify-self-end">
              <InputGroup className="h-7 w-full sm:w-64">
                <InputGroupInput
                  aria-label="Search authorizations"
                  className="h-7"
                  placeholder="Search patient, PA, or provider..."
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
                <InputGroupAddon>
                  <Search />
                </InputGroupAddon>
              </InputGroup>
              <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as (typeof statusOptions)[number])}>
                <SelectTrigger size="sm">
                  <span className="text-muted-foreground">Status:</span>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent position="popper" align="end">
                  <SelectGroup>
                    {statusOptions.map((status) => (
                      <SelectItem key={status} value={status}>
                        {status}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
              <Select value={payerFilter} onValueChange={(value) => setPayerFilter(value as (typeof payerOptions)[number])}>
                <SelectTrigger size="sm">
                  <span className="text-muted-foreground">Payer:</span>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent position="popper" align="end">
                  <SelectGroup>
                    {payerOptions.map((payer) => (
                      <SelectItem key={payer} value={payer}>
                        {payer}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
            </CardAction>
          </CardHeader>
          <CardContent className="flex flex-col gap-4 px-0">
            <Tabs value={activeView} onValueChange={(value) => setActiveView(value as AuthorizationView)}>
              <TabsList
                variant="line"
                className="w-full justify-start gap-2 overflow-x-auto border-b px-4 *:data-[slot=tabs-trigger]:flex-none"
              >
                <TabsTrigger value="all">All authorizations</TabsTrigger>
                <TabsTrigger value="review">Review queue</TabsTrigger>
                <TabsTrigger value="decisions">Decisions</TabsTrigger>
              </TabsList>
              <TabsContent value={activeView} className="px-4">
                {filteredAuthorizations.length ? (
                  <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    {filteredAuthorizations.map((authorization) => (
                      <AuthorizationCard
                        authorization={authorization}
                        key={authorization.id}
                        onReview={setSelectedAuthorizationId}
                      />
                    ))}
                  </div>
                ) : (
                  <Empty className="min-h-64">
                    <EmptyHeader>
                      <EmptyMedia variant="icon">
                        <Search />
                      </EmptyMedia>
                      <EmptyTitle>No authorizations found</EmptyTitle>
                      <EmptyDescription>Adjust the search or filter selections to review a different request.</EmptyDescription>
                    </EmptyHeader>
                  </Empty>
                )}
              </TabsContent>
            </Tabs>
          </CardContent>
          <CardFooter className="justify-between gap-2">
            <p className="text-muted-foreground text-sm">
              Showing {filteredAuthorizations.length} of {authorizationRows.length} authorizations
            </p>
            <Badge variant="outline">{reviewQueue.length} in review</Badge>
          </CardFooter>
        </Card>

        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader>
              <CardTitle>Review panel</CardTitle>
              <CardDescription>Selected request and workflow action.</CardDescription>
            </CardHeader>
            {selectedAuthorization ? (
              <>
                <CardContent className="flex flex-col gap-4">
                  <div className="flex flex-col gap-1">
                    <p className="font-medium">{selectedAuthorization.patient}</p>
                    <p className="text-muted-foreground text-sm">
                      {selectedAuthorization.id} · {selectedAuthorization.mrn}
                    </p>
                  </div>
                  <dl className="flex flex-col gap-3 text-sm">
                    <div className="flex items-center justify-between gap-4">
                      <dt className="text-muted-foreground">Workflow status</dt>
                      <dd>
                        <Badge variant="outline">{selectedAuthorization.status}</Badge>
                      </dd>
                    </div>
                    <div className="flex items-center justify-between gap-4">
                      <dt className="text-muted-foreground">Linked referral</dt>
                      <dd className="font-medium">{selectedAuthorization.referralId}</dd>
                    </div>
                    <div className="flex items-center justify-between gap-4">
                      <dt className="text-muted-foreground">Clinical records</dt>
                      <dd className="font-medium">{selectedAuthorization.documents} attached</dd>
                    </div>
                  </dl>
                  <div className="flex flex-col gap-1 border-t pt-4">
                    <p className="text-muted-foreground text-xs">Latest audit activity</p>
                    <p className="text-sm">
                      {selectedAuthorization.updatedBy} · {selectedAuthorization.updatedAt}
                    </p>
                  </div>
                </CardContent>
                <CardFooter className="justify-end gap-2">
                  <Button size="sm" variant="outline" onClick={() => setSelectedAuthorizationId("")}>
                    Clear
                  </Button>
                  {nextAction ? (
                    <Button
                      size="sm"
                      onClick={() => updateAuthorizationStatus(selectedAuthorization.id, nextAction.status)}
                    >
                      {nextAction.label}
                    </Button>
                  ) : null}
                </CardFooter>
              </>
            ) : null}
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Priority review queue</CardTitle>
              <CardDescription>Requests that need coordinator attention today.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
              {reviewQueue.slice(0, 3).map((authorization) => (
                <button
                  className="flex items-center justify-between gap-3 rounded-lg border p-3 text-left transition-colors hover:bg-muted"
                  key={authorization.id}
                  onClick={() => setSelectedAuthorizationId(authorization.id)}
                  type="button"
                >
                  <div className="min-w-0">
                    <p className="truncate font-medium text-sm">{authorization.patient}</p>
                    <p className="truncate text-muted-foreground text-xs">{authorization.service}</p>
                  </div>
                  <Badge variant={authorization.status === "Pending" ? "secondary" : "outline"}>{authorization.status}</Badge>
                </button>
              ))}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
