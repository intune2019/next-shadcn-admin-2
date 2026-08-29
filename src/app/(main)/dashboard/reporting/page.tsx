import { AnalyticsKpiStrip } from "../analytics/_components/analytics-kpi-strip";
import { RealtimeVisitors } from "../analytics/_components/realtime-visitors";
import { TopPages } from "../analytics/_components/top-pages";
import { TopTrafficSources } from "../analytics/_components/top-traffic-sources";
import { TrafficQuality } from "../analytics/_components/traffic-quality";

import "@/styles/flag-icons/flags.css";

export default function Page() {
  return (
    <div className="flex flex-col gap-4">
      <div className="space-y-1">
        <h1 className="text-3xl tracking-tight">Reporting Dashboard</h1>
        <p className="text-muted-foreground text-sm">Monitor performance, engagement, and operational signals in one view.</p>
      </div>

      <AnalyticsKpiStrip />

      <div className="grid grid-cols-1 items-stretch gap-4 xl:grid-cols-12">
        <div className="xl:col-span-7">
          <TrafficQuality />
        </div>
        <div className="xl:col-span-5">
          <RealtimeVisitors />
        </div>
      </div>

      <div className="grid grid-cols-1 items-stretch gap-4 xl:grid-cols-12">
        <div className="xl:col-span-7">
          <TopPages />
        </div>
        <div className="xl:col-span-5 xl:col-start-8">
          <TopTrafficSources />
        </div>
      </div>
    </div>
  );
}
