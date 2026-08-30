import { CheckSquare, FileText, Focus, Orbit, Upload } from "lucide-react";

import { Button } from "@/components/ui/button";

const quickActions = [
  { label: "New patient", icon: FileText },
  { label: "Start encounter", icon: CheckSquare },
  { label: "New referral", icon: Orbit },
  { label: "Prior authorization", icon: Focus },
  { label: "Upload document", icon: Upload },
] as const;

export function QuickActions({ showTitle = true }: { showTitle?: boolean } = {}) {
  return (
    <section className="flex flex-col gap-2">
      {showTitle ? <h2 className="text-xl tracking-tight">Clinical actions</h2> : null}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        {quickActions.map((action) => (
          <Button key={action.label} variant="outline" className="justify-start">
            <action.icon data-icon="inline-start" />
            {action.label}
          </Button>
        ))}
      </div>
    </section>
  );
}
