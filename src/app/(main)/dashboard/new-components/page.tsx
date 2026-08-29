import { Globe, Search } from "lucide-react";

import { GlobeCdn } from "@/components/ui/cobe-globe-cdn";
import InputModel from "@/components/ui/input-model";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Globe className="size-5" />
        <h1 className="text-3xl tracking-tight">New Components</h1>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Search input</CardTitle>
            <CardDescription>A compact input field for filtering component collections.</CardDescription>
          </CardHeader>
          <CardContent className="flex min-h-32 items-center">
            <InputGroup>
              <InputGroupAddon>
                <Search />
              </InputGroupAddon>
              <InputGroupInput aria-label="Search components" placeholder="Search components..." />
            </InputGroup>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>CDN globe</CardTitle>
            <CardDescription>Interactive globe with live traffic markers and network arcs.</CardDescription>
          </CardHeader>
          <CardContent className="flex items-center justify-center bg-white p-4 dark:bg-white">
            <GlobeCdn className="w-full max-w-sm" />
          </CardContent>
        </Card>

        <div className="md:col-span-2">
          <InputModel />
        </div>
      </div>
    </div>
  );
}
