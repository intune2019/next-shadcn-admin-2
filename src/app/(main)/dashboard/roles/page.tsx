import { GlobeCdnDemo } from "@/components/ui/cobe-globe-cdn";

import { Roles } from "./_components/roles";
import { roles } from "./_components/roles-table/data";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <GlobeCdnDemo />
      <Roles roles={roles} />
    </div>
  );
}
