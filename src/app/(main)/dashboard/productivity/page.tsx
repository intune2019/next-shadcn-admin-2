import { CalendarPanel } from "./_components/calendar-panel";
import { OpportunitiesSection } from "../crm/_components/opportunities-section";
import { TaskReminders } from "../crm/_components/task-reminders";
import { KpiStrip } from "../ecommerce/_components/kpi-strip";
import { folders } from "../file-manager/_components/data";
import { FoldersSection } from "../file-manager/_components/folders-section";
import { FocusCard } from "./_components/focus-card";
import { ProjectsSection } from "./_components/projects-section";
import { QuickActions } from "./_components/quick-actions";
import { QuoteCard } from "./_components/quote-card";
import { RecentNotesCard } from "./_components/recent-notes-card";
import { SummaryCards } from "./_components/summary-cards";
import { TasksSection } from "./_components/tasks-section";
import { WeeklySummaryCard } from "./_components/weekly-summary-card";

export default function Page() {
  return (
    <div className="grid gap-4 lg:grid-cols-12">
      <section className="flex min-w-0 flex-col gap-4 lg:col-span-9">
        <div className="flex flex-col gap-1">
          <h1 className="text-xl text-foreground leading-none tracking-tight">Good morning, Arham.</h1>
          <p className="text-xs text-muted-foreground leading-none">Let&apos;s make today productive and meaningful.</p>
        </div>
        <QuickActions showTitle={false} />
        <ProjectsSection />
        <TasksSection />
        <KpiStrip />
        <OpportunitiesSection />
      </section>

      <aside className="flex min-w-0 flex-col gap-4 lg:col-span-3">
        <CalendarPanel />
        <FocusCard />
        <TaskReminders showUpcomingMeetings={false} />
        <WeeklySummaryCard />
        <RecentNotesCard />
        <SummaryCards className="grid-cols-1 md:grid-cols-1 [&>*:last-child]:hidden" />
        <FoldersSection folders={folders} className="grid-cols-1 sm:grid-cols-1 xl:grid-cols-1" />
        <QuoteCard />
      </aside>
    </div>
  );
}
