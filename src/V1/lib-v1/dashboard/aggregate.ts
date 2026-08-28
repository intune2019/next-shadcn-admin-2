export function groupCount(rows: { key: string | null }[]): { label: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const row of rows) {
    const label = row.key ?? "unspecified";
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return Array.from(counts.entries())
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count);
}
