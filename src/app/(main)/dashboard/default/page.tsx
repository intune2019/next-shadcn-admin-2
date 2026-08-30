import { Badge } from "@/components/ui/badge";

import { TaskReminders } from "../crm/_components/task-reminders";
import { CalendarPanel } from "../productivity/_components/calendar-panel";
import { QuickActions } from "../productivity/_components/quick-actions";
import { SummaryCards } from "../productivity/_components/summary-cards";
import { TasksSection } from "../productivity/_components/tasks-section";
import { MetricCards } from "./_components/metric-cards";
import { PerformanceOverview } from "./_components/performance-overview";
import { SubscriberOverview } from "./_components/subscriber-overview";

export default function Page() {
  return (
    <div className="@container/main flex flex-col gap-4">
      <div className="flex flex-col gap-2 sm:gap-3 md:flex-row md:items-end md:justify-between">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-3xl tracking-tight">Clinical command center</h1>
            <Badge variant="outline">Live workspace</Badge>
          </div>
          <p className="max-w-2xl text-muted-foreground text-sm">A connected view of patients, care delivery, and practice performance.</p>
        </div>
        <Badge variant="secondary">Northstar Health · All locations</Badge>
      </div>
      <MetricCards />
      <PerformanceOverview />
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <section className="flex min-w-0 flex-col gap-4 xl:col-span-8">
          <QuickActions />
          <TasksSection />
        </section>
        <aside className="flex min-w-0 flex-col gap-4 xl:col-span-4">
          <CalendarPanel />
          <TaskReminders showUpcomingMeetings={false} />
          <SummaryCards className="grid-cols-1 md:grid-cols-1" />
        </aside>
      </div>
      <SubscriberOverview />
    </div>
  );
}
