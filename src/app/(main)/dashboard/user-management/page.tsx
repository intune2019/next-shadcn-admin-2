import { roles } from "../roles/_components/roles-table/data";
import { Roles } from "../roles/_components/roles";
import { users } from "../users/_components/data";
import { Users } from "../users/_components/users";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="space-y-1">
        <h1 className="text-3xl tracking-tight">User Management Dashboard</h1>
        <p className="text-muted-foreground text-sm">Manage people, roles, access, and workspace participation.</p>
      </div>

      <Users users={users} />
      <Roles roles={roles} />
    </div>
  );
}
