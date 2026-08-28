import { recentLeadsData } from "./_components/crm.config";
import { OpportunitiesSection } from "../../crm/_components/opportunities-section";
import { PipelineActivity } from "../../crm/_components/pipeline-activity";
import { TaskReminders } from "../../crm/_components/task-reminders";
import { KpiStrip } from "../../ecommerce/_components/kpi-strip";
import { InsightCards } from "./_components/insight-cards";
import { OperationalCards } from "./_components/operational-cards";
import { OverviewCards } from "./_components/overview-cards";

export default function Page() {
  return (
    <div className="flex flex-col gap-4 md:gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-3xl leading-none tracking-tight">CRM Command Center</h1>
        <p className="text-muted-foreground text-sm">Keep your pipeline, revenue, and next actions moving in one place.</p>
      </div>

      <KpiStrip />

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="min-w-0 xl:col-span-8">
          <PipelineActivity />
        </div>
        <div className="min-w-0 xl:col-span-4">
          <TaskReminders />
        </div>
      </div>

      <OverviewCards />

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <InsightCards />
        <OperationalCards />
      </div>

      <OpportunitiesSection />
    </div>
  );
}
