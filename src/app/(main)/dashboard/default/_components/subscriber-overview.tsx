"use client";

import { Download } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import customersData from "./data.json";
import type { RecentCustomerRow } from "./recent-customers-table/schema";
import { RecentCustomersTable } from "./recent-customers-table/table";

const customers = customersData as RecentCustomerRow[];

export function SubscriberOverview() {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="leading-none">18,426 Patients</CardTitle>
        <CardDescription>Recent patient records with care team, coverage, status, and last visit.</CardDescription>
        <CardAction>
          <Button variant="outline" size="sm">
            <Download />
            Export registry
          </Button>
        </CardAction>
      </CardHeader>

      <CardContent className="overflow-x-auto pt-0">
        <RecentCustomersTable data={customers} />
      </CardContent>
    </Card>
  );
}
