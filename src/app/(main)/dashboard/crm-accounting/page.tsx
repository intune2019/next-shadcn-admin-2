import { KpiCards } from "../crm/_components/kpi-cards";
import { OpportunitiesSection } from "../crm/_components/opportunities-section";
import { PipelineActivity } from "../crm/_components/pipeline-activity";
import { TaskReminders } from "../crm/_components/task-reminders";
import { BalanceDistributionCard } from "../finance/_components/balance-distribution-card";
import { IncomeBreakdown } from "../finance/_components/income-breakdown";
import { OverviewKpis } from "../finance/_components/overview-kpis";
import { QuickActions } from "../finance/_components/quick-actions";
import { TransactionsOverviewCard } from "../finance/_components/transactions-overview-card";
import { UpcomingTransactions } from "../finance/_components/upcoming-transactions";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="space-y-1">
        <h1 className="text-3xl tracking-tight">CRM & Accounting Dashboard</h1>
        <p className="text-muted-foreground text-sm">Keep customer momentum, cash flow, and commercial work in one view.</p>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="flex flex-col gap-4 xl:col-span-7">
          <KpiCards />
          <PipelineActivity />
        </div>
        <div className="flex flex-col gap-4 xl:col-span-5">
          <OverviewKpis />
          <IncomeBreakdown />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="xl:col-span-7">
          <TransactionsOverviewCard />
        </div>
        <div className="xl:col-span-5">
          <BalanceDistributionCard />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-12">
        <div className="xl:col-span-4">
          <TaskReminders />
        </div>
        <div className="xl:col-span-4">
          <UpcomingTransactions />
        </div>
        <div className="xl:col-span-4">
          <QuickActions />
        </div>
      </div>

      <OpportunitiesSection />
    </div>
  );
}
