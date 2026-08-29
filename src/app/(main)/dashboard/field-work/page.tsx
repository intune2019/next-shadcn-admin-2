import { FoldersSection } from "../file-manager/_components/folders-section";
import { folders } from "../file-manager/_components/data";
import { InfrastructureHeader } from "../infrastructure/_components/infrastructure-header";
import { infrastructureGroups } from "../infrastructure/_components/infrastructure-data";
import { ProjectEnvironments } from "../infrastructure/_components/project-environments";

import "@/styles/flag-icons/flags.css";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="space-y-1">
        <h1 className="text-3xl tracking-tight">Field Work Dashboard</h1>
        <p className="text-muted-foreground text-sm">Coordinate field operations, resources, and working documents.</p>
      </div>

      <InfrastructureHeader />

      <div className="flex flex-col gap-4">
        {infrastructureGroups.map((group) => (
          <ProjectEnvironments key={group.name} group={group} />
        ))}
      </div>

      <FoldersSection folders={folders} />
    </div>
  );
}
