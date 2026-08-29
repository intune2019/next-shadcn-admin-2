"use client";

import { addMonths, endOfMonth, startOfMonth, subDays, subMonths } from "date-fns";
import { Eye, Link2, Trash2 } from "lucide-react";
import { useState } from "react";

import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuTrigger } from "@/components/ui/context-menu";
import {
  GanttCreateMarkerTrigger,
  GanttFeatureItem,
  GanttFeatureList,
  GanttFeatureListGroup,
  GanttHeader,
  GanttMarker,
  GanttProvider,
  GanttSidebar,
  GanttSidebarGroup,
  GanttSidebarItem,
  GanttTimeline,
  GanttToday,
} from "@/components/ui/gantt";

const today = new Date();

const exampleStatuses = [
  { id: "1", name: "Planned", color: "#6B7280" },
  { id: "2", name: "In Progress", color: "#F59E0B" },
  { id: "3", name: "Done", color: "#10B981" },
];

const exampleFeatures = [
  {
    id: "1",
    name: "AI Scene Analysis",
    startAt: startOfMonth(subMonths(today, 6)),
    endAt: subDays(endOfMonth(today), 5),
    status: exampleStatuses[0],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "2",
    name: "Collaborative Editing",
    startAt: startOfMonth(subMonths(today, 5)),
    endAt: subDays(endOfMonth(today), 5),
    status: exampleStatuses[1],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "3",
    name: "AI-Powered Color Grading",
    startAt: startOfMonth(subMonths(today, 4)),
    endAt: subDays(endOfMonth(today), 5),
    status: exampleStatuses[2],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "4",
    name: "Real-time Video Chat",
    startAt: startOfMonth(subMonths(today, 3)),
    endAt: subDays(endOfMonth(today), 12),
    status: exampleStatuses[0],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "5",
    name: "AI Voice-to-Text Subtitles",
    startAt: startOfMonth(subMonths(today, 2)),
    endAt: subDays(endOfMonth(today), 5),
    status: exampleStatuses[1],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "6",
    name: "Cloud Asset Management",
    startAt: startOfMonth(subMonths(today, 1)),
    endAt: endOfMonth(today),
    status: exampleStatuses[2],
    group: { id: "3", name: "Cloud Infrastructure" },
  },
  {
    id: "7",
    name: "AI-Assisted Video Transitions",
    startAt: startOfMonth(today),
    endAt: endOfMonth(addMonths(today, 1)),
    status: exampleStatuses[0],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "8",
    name: "Version Control System",
    startAt: startOfMonth(addMonths(today, 1)),
    endAt: endOfMonth(addMonths(today, 2)),
    status: exampleStatuses[1],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "9",
    name: "AI Content-Aware Fill",
    startAt: startOfMonth(addMonths(today, 2)),
    endAt: endOfMonth(addMonths(today, 3)),
    status: exampleStatuses[2],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "10",
    name: "Multi-User Permissions",
    startAt: startOfMonth(addMonths(today, 3)),
    endAt: endOfMonth(addMonths(today, 4)),
    status: exampleStatuses[0],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "11",
    name: "AI-Powered Audio Enhancement",
    startAt: startOfMonth(addMonths(today, 4)),
    endAt: endOfMonth(addMonths(today, 5)),
    status: exampleStatuses[1],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "12",
    name: "Real-time Project Analytics",
    startAt: startOfMonth(addMonths(today, 5)),
    endAt: endOfMonth(addMonths(today, 6)),
    status: exampleStatuses[2],
    group: { id: "3", name: "Cloud Infrastructure" },
  },
  {
    id: "13",
    name: "AI Scene Recommendations",
    startAt: startOfMonth(addMonths(today, 6)),
    endAt: endOfMonth(addMonths(today, 7)),
    status: exampleStatuses[0],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "14",
    name: "Collaborative Storyboarding",
    startAt: startOfMonth(addMonths(today, 7)),
    endAt: endOfMonth(addMonths(today, 8)),
    status: exampleStatuses[1],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "15",
    name: "AI-Driven Video Compression",
    startAt: startOfMonth(addMonths(today, 8)),
    endAt: endOfMonth(addMonths(today, 9)),
    status: exampleStatuses[2],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "16",
    name: "Global CDN Integration",
    startAt: startOfMonth(addMonths(today, 9)),
    endAt: endOfMonth(addMonths(today, 10)),
    status: exampleStatuses[0],
    group: { id: "3", name: "Cloud Infrastructure" },
  },
  {
    id: "17",
    name: "AI Object Tracking",
    startAt: startOfMonth(addMonths(today, 10)),
    endAt: endOfMonth(addMonths(today, 11)),
    status: exampleStatuses[1],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "18",
    name: "Real-time Language Translation",
    startAt: startOfMonth(addMonths(today, 11)),
    endAt: endOfMonth(addMonths(today, 12)),
    status: exampleStatuses[2],
    group: { id: "2", name: "Collaboration Tools" },
  },
  {
    id: "19",
    name: "AI-Powered Video Summarization",
    startAt: startOfMonth(addMonths(today, 12)),
    endAt: endOfMonth(addMonths(today, 13)),
    status: exampleStatuses[0],
    group: { id: "1", name: "Core AI Features" },
  },
  {
    id: "20",
    name: "Blockchain-based Asset Licensing",
    startAt: startOfMonth(addMonths(today, 13)),
    endAt: endOfMonth(addMonths(today, 14)),
    status: exampleStatuses[1],
    group: { id: "3", name: "Cloud Infrastructure" },
  },
];

const exampleMarkers = [
  { id: "1", date: startOfMonth(subMonths(today, 3)), label: "Project Kickoff", className: "bg-blue-100 text-blue-900" },
  { id: "2", date: subMonths(endOfMonth(today), 2), label: "Phase 1 Completion", className: "bg-green-100 text-green-900" },
  { id: "3", date: startOfMonth(addMonths(today, 3)), label: "Beta Release", className: "bg-purple-100 text-purple-900" },
  { id: "4", date: endOfMonth(addMonths(today, 6)), label: "Version 1.0 Launch", className: "bg-red-100 text-red-900" },
  { id: "5", date: startOfMonth(addMonths(today, 9)), label: "User Feedback Review", className: "bg-orange-100 text-orange-900" },
  { id: "6", date: endOfMonth(addMonths(today, 12)), label: "Annual Performance Evaluation", className: "bg-teal-100 text-teal-900" },
];

export default function GanttDemo() {
  const [features, setFeatures] = useState(exampleFeatures);
  const groupedFeatures = features.reduce<Record<string, typeof features>>((groups, feature) => {
    const groupName = feature.group.name;
    return { ...groups, [groupName]: [...(groups[groupName] || []), feature] };
  }, {});
  const sortedGroupedFeatures = Object.fromEntries(
    Object.entries(groupedFeatures).sort(([nameA], [nameB]) => nameA.localeCompare(nameB)),
  );

  const handleRemoveFeature = (id: string) => setFeatures((prev) => prev.filter((feature) => feature.id !== id));
  const handleRemoveMarker = (id: string) => console.log(`Remove marker: ${id}`);
  const handleMoveFeature = (id: string, startAt: Date, endAt: Date | null) => {
    if (!endAt) return;
    setFeatures((prev) => prev.map((feature) => (feature.id === id ? { ...feature, startAt, endAt } : feature)));
  };

  return (
    <GanttProvider range="monthly" zoom={100} className="h-[500px] border">
      <GanttSidebar>
        {Object.entries(sortedGroupedFeatures).map(([group, groupFeatures]) => (
          <GanttSidebarGroup key={group} name={group}>
            {groupFeatures.map((feature) => <GanttSidebarItem key={feature.id} feature={feature} />)}
          </GanttSidebarGroup>
        ))}
      </GanttSidebar>
      <GanttTimeline>
        <GanttHeader />
        <GanttFeatureList>
          {Object.entries(sortedGroupedFeatures).map(([group, groupFeatures]) => (
            <GanttFeatureListGroup key={group}>
              {groupFeatures.map((feature) => (
                <div className="flex" key={feature.id}>
                  <ContextMenu>
                    <ContextMenuTrigger asChild>
                      <button type="button"><GanttFeatureItem onMove={handleMoveFeature} {...feature} /></button>
                    </ContextMenuTrigger>
                    <ContextMenuContent>
                      <ContextMenuItem className="flex items-center gap-2"><Eye size={16} className="text-muted-foreground" />View feature</ContextMenuItem>
                      <ContextMenuItem className="flex items-center gap-2"><Link2 size={16} className="text-muted-foreground" />Copy link</ContextMenuItem>
                      <ContextMenuItem className="flex items-center gap-2 text-destructive" onClick={() => handleRemoveFeature(feature.id)}><Trash2 size={16} />Remove from roadmap</ContextMenuItem>
                    </ContextMenuContent>
                  </ContextMenu>
                </div>
              ))}
            </GanttFeatureListGroup>
          ))}
        </GanttFeatureList>
        {exampleMarkers.map((marker) => <GanttMarker key={marker.id} {...marker} onRemove={handleRemoveMarker} />)}
        <GanttToday />
        <GanttCreateMarkerTrigger onCreateMarker={() => undefined} />
      </GanttTimeline>
    </GanttProvider>
  );
}
