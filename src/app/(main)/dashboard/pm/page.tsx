import { CalendarPanel } from "../productivity/_components/calendar-panel";
import { FocusCard } from "../productivity/_components/focus-card";
import { ProjectsSection } from "../productivity/_components/projects-section";
import { QuickActions } from "../productivity/_components/quick-actions";
import { QuoteCard } from "../productivity/_components/quote-card";
import { RecentNotesCard } from "../productivity/_components/recent-notes-card";
import { SummaryCards } from "../productivity/_components/summary-cards";
import { TasksSection } from "../productivity/_components/tasks-section";
import { WeeklySummaryCard } from "../productivity/_components/weekly-summary-card";

export default function Page() {
  return (
    <div className="grid gap-4 lg:grid-cols-12">
      <section className="flex min-w-0 flex-col gap-4 lg:col-span-9">
        <div className="flex flex-col gap-1">
          <h1 className="text-xl text-foreground leading-none tracking-tight">PM Dashboard</h1>
          <p className="text-xs text-muted-foreground leading-none">Plan, prioritize, and move project work forward.</p>
        </div>
        <QuickActions showTitle={false} />
        <ProjectsSection />
        <TasksSection />
        <WeeklySummaryCard />
      </section>

      <aside className="flex min-w-0 flex-col gap-4 lg:col-span-3">
        <CalendarPanel />
        <FocusCard />
        <SummaryCards className="grid-cols-1 md:grid-cols-1 [&>*:last-child]:hidden" />
        <RecentNotesCard />
        <QuoteCard />
      </aside>
    </div>
  );
}
