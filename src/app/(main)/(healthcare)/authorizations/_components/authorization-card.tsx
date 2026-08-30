import { FileText, Link2 } from "lucide-react";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";

import type { Authorization, AuthorizationStatus } from "./data";

const statusVariants: Record<AuthorizationStatus, "default" | "destructive" | "outline" | "secondary"> = {
  Draft: "outline",
  Submitted: "secondary",
  Pending: "secondary",
  Approved: "default",
  Denied: "destructive",
  Expired: "destructive",
};

export function AuthorizationCard({
  authorization,
  onReview,
}: {
  authorization: Authorization;
  onReview: (authorizationId: string) => void;
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="text-sm">{authorization.patient}</CardTitle>
        <CardDescription>
          {authorization.mrn} · {authorization.id}
        </CardDescription>
        <CardAction>
          <Badge variant={statusVariants[authorization.status]}>{authorization.status}</Badge>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex items-center gap-3">
          <Avatar>
            <AvatarFallback>{authorization.patientInitials}</AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <p className="truncate font-medium">{authorization.service}</p>
            <p className="text-muted-foreground text-sm">
              {authorization.provider} · {authorization.location}
            </p>
          </div>
        </div>
        <dl className="grid grid-cols-2 gap-4 text-sm">
          <div className="flex flex-col gap-1">
            <dt className="text-muted-foreground">Payer</dt>
            <dd className="font-medium">{authorization.payer}</dd>
          </div>
          <div className="flex flex-col gap-1">
            <dt className="text-muted-foreground">Requested units</dt>
            <dd className="font-medium">
              {authorization.approvedUnits
                ? `${authorization.approvedUnits} approved of ${authorization.requestedUnits}`
                : authorization.requestedUnits}
            </dd>
          </div>
        </dl>
        <div className="flex flex-wrap items-center gap-2">
          <Badge className="rounded-sm" variant="outline">
            <Link2 data-icon="inline-start" />
            {authorization.referralId}
          </Badge>
          <Badge className="rounded-sm" variant="outline">
            <FileText data-icon="inline-start" />
            {authorization.documents} documents
          </Badge>
          {authorization.priority === "Urgent" ? <Badge variant="destructive">Urgent</Badge> : null}
        </div>
      </CardContent>
      <CardFooter className="justify-between gap-2">
        <div className="min-w-0">
          <p className="text-muted-foreground text-xs">Decision due</p>
          <p className="truncate font-medium text-sm">{authorization.decisionDue}</p>
        </div>
        <Button size="sm" variant="outline" onClick={() => onReview(authorization.id)}>
          Review
        </Button>
      </CardFooter>
    </Card>
  );
}
