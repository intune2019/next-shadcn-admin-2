import { Globe, Search } from "lucide-react";

import { GlobeCdnDemo } from "@/components/ui/cobe-globe-cdn";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Globe className="size-5" />
        <h1 className="text-3xl tracking-tight">New Components</h1>
      </div>

      <InputGroup className="max-w-md">
        <InputGroupAddon>
          <Search />
        </InputGroupAddon>
        <InputGroupInput aria-label="Search components" placeholder="Search components..." />
      </InputGroup>

      <GlobeCdnDemo />
    </div>
  );
}
