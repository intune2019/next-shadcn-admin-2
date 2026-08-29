"use client";

import {
  addDays,
  addMonths,
  endOfDay,
  endOfMonth,
  endOfWeek,
  format,
  isEqual,
  isSameDay,
  isSameMonth,
  isToday,
  isValid,
  isWithinInterval,
  parse,
  startOfDay,
  startOfMonth,
  startOfWeek,
  subDays,
  subMonths,
  subWeeks,
  subYears,
} from "date-fns";
import { formatInTimeZone, fromZonedTime } from "date-fns-tz";
import { CalendarDays, ChevronDown, ChevronLeft, ChevronRight, Clock3, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";

export interface RangeValue {
  start: Date | null;
  end: Date | null;
}

type RangePreset = {
  text: string;
  start: Date;
  end: Date;
};

interface DateRangeCalendarProps {
  allowClear?: boolean;
  compact?: boolean;
  isDocsPage?: boolean;
  stacked?: boolean;
  horizontalLayout?: boolean;
  showTimeInput?: boolean;
  popoverAlignment?: "start" | "center" | "end";
  value: RangeValue | null;
  onChange: (date: RangeValue | null) => void;
  presets?: Record<string, RangePreset>;
  presetIndex?: number;
  minValue?: Date;
  maxValue?: Date;
}

const getTimezoneOptions = () => {
  const localTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return [
    { value: "UTC", label: "UTC" },
    { value: localTimezone, label: `Local (${localTimezone})` },
  ].filter((option, index, options) => options.findIndex((item) => item.value === option.value) === index);
};

const formatDateRange = (start: Date, end: Date, timezone: string) => {
  const sameDay = isSameDay(start, end);
  const startHasTime = !isEqual(start, startOfDay(start));
  const endHasTime = !isEqual(end, endOfDay(end));
  const formatDate = (date: Date, withTime: boolean) =>
    formatInTimeZone(date, timezone, withTime ? "MMM d, HH:mm" : "MMM d, yyyy");

  if (sameDay) {
    return formatInTimeZone(start, timezone, startHasTime || endHasTime ? "EEE, MMM d, HH:mm" : "EEE, MMM d");
  }

  return `${formatDate(start, startHasTime)} - ${formatDate(end, endHasTime)}`;
};

const getDefaultPresets = () => {
  const now = new Date();
  return {
    today: { text: "Today", start: startOfDay(now), end: endOfDay(now) },
    yesterday: {
      text: "Yesterday",
      start: startOfDay(subDays(now, 1)),
      end: endOfDay(subDays(now, 1)),
    },
    last7: { text: "Last 7 Days", start: startOfDay(subDays(now, 7)), end: endOfDay(now) },
    last30: { text: "Last 30 Days", start: startOfDay(subDays(now, 30)), end: endOfDay(now) },
    lastWeek: {
      text: "Last Week",
      start: startOfWeek(subWeeks(now, 1), { weekStartsOn: 1 }),
      end: endOfWeek(subWeeks(now, 1), { weekStartsOn: 1 }),
    },
    lastMonth: {
      text: "Last Month",
      start: startOfMonth(subMonths(now, 1)),
      end: endOfMonth(subMonths(now, 1)),
    },
    lastYear: {
      text: "Last Year",
      start: startOfDay(subYears(now, 1)),
      end: endOfDay(now),
    },
  } satisfies Record<string, RangePreset>;
};

export function DateRangeCalendar({
  allowClear = false,
  compact = false,
  horizontalLayout = false,
  showTimeInput = true,
  popoverAlignment = "start",
  value,
  onChange,
  presets,
  presetIndex,
  minValue,
  maxValue,
}: DateRangeCalendarProps) {
  const calendarRef = useRef<HTMLDivElement>(null);
  const timezoneOptions = useMemo(getTimezoneOptions, []);
  const [isOpen, setIsOpen] = useState(false);
  const [currentDate, setCurrentDate] = useState(() => value?.start ?? new Date());
  const [hoverDate, setHoverDate] = useState<Date | null>(null);
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectedTimezone, setSelectedTimezone] = useState(timezoneOptions[1]?.value ?? "UTC");
  const [startDate, setStartDate] = useState("");
  const [startTime, setStartTime] = useState("00:00");
  const [endDate, setEndDate] = useState("");
  const [endTime, setEndTime] = useState("23:59");
  const [dateError, setDateError] = useState(false);
  const [timeError, setTimeError] = useState(false);

  const availablePresets = presets ?? getDefaultPresets();
  const days = useMemo(() => {
    const result: Date[] = [];
    let day = startOfWeek(startOfMonth(currentDate), { weekStartsOn: 1 });
    const lastDay = endOfWeek(endOfMonth(currentDate), { weekStartsOn: 1 });

    while (day <= lastDay) {
      result.push(day);
      day = addDays(day, 1);
    }

    return result;
  }, [currentDate]);

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      if (calendarRef.current && !calendarRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, []);

  useEffect(() => {
    const start = value?.start ?? new Date();
    const end = value?.end ?? new Date();
    setStartDate(formatInTimeZone(start, selectedTimezone, "MMM dd, yyyy"));
    setStartTime(formatInTimeZone(start, selectedTimezone, "HH:mm"));
    setEndDate(formatInTimeZone(end, selectedTimezone, "MMM dd, yyyy"));
    setEndTime(formatInTimeZone(end, selectedTimezone, "HH:mm"));
  }, [selectedTimezone, value]);

  useEffect(() => {
    if (presetIndex === undefined) return;
    const preset = Object.values(availablePresets)[presetIndex];
    if (preset) onChange({ start: preset.start, end: preset.end });
  }, [availablePresets, onChange, presetIndex]);

  const isAllowedDate = (day: Date) => (minValue ? day >= minValue : true) && (maxValue ? day <= maxValue : true);

  const handleDateClick = (day: Date) => {
    if (!isAllowedDate(day)) return;

    if (!value?.start || value.end) {
      onChange({ start: startOfDay(day), end: null });
      setHoverDate(day);
      setIsSelecting(true);
      return;
    }

    if (day >= value.start) {
      onChange({ start: value.start, end: endOfDay(day) });
    } else {
      onChange({ start: startOfDay(day), end: endOfDay(value.start) });
    }
    setIsSelecting(false);
    setHoverDate(null);
  };

  const handleApply = () => {
    const parsedStartDate = parse(startDate, "MMM dd, yyyy", new Date());
    const parsedEndDate = parse(endDate, "MMM dd, yyyy", new Date());
    const parsedStartTime = showTimeInput ? parse(startTime, "HH:mm", new Date()) : startOfDay(parsedStartDate);
    const parsedEndTime = showTimeInput ? parse(endTime, "HH:mm", new Date()) : endOfDay(parsedEndDate);
    const hasDateError = !isValid(parsedStartDate) || !isValid(parsedEndDate);
    const hasTimeError = showTimeInput && (!isValid(parsedStartTime) || !isValid(parsedEndTime));

    setDateError(hasDateError);
    setTimeError(hasTimeError);
    if (hasDateError || hasTimeError) return;

    const start = parse(`${startDate} ${startTime}`, "MMM dd, yyyy HH:mm", new Date());
    const end = parse(`${endDate} ${endTime}`, "MMM dd, yyyy HH:mm", new Date());
    onChange({ start: fromZonedTime(start, selectedTimezone), end: fromZonedTime(end, selectedTimezone) });
    setIsOpen(false);
  };

  const popupAlignment =
    popoverAlignment === "center"
      ? "left-1/2 -translate-x-1/2"
      : popoverAlignment === "end"
        ? "right-0"
        : "left-0";

  return (
    <div ref={calendarRef} className="relative inline-block text-sm">
      <Button
        type="button"
        variant="outline"
        onClick={() => setIsOpen((open) => !open)}
        className={`justify-start gap-2 ${compact ? "w-44" : "w-64"}`}
        aria-expanded={isOpen}
      >
        <CalendarDays className="size-4" />
        <span className="truncate">{value?.start && value.end ? formatDateRange(value.start, value.end, selectedTimezone) : "Select Date Range"}</span>
        {value?.start && value.end && allowClear ? (
          <span
            role="button"
            tabIndex={0}
            aria-label="Clear date range"
            className="ml-auto rounded p-0.5 hover:bg-muted"
            onClick={(event) => {
              event.stopPropagation();
              onChange(null);
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") onChange(null);
            }}
          >
            <X className="size-3.5" />
          </span>
        ) : (
          <ChevronDown className={`ml-auto size-4 transition-transform ${isOpen ? "rotate-180" : ""}`} />
        )}
      </Button>

      {isOpen && (
        <div
          className={`absolute top-full z-50 mt-1 rounded-xl border border-border bg-popover p-3 text-popover-foreground shadow-lg ${
            horizontalLayout ? "w-[462px]" : "w-[280px]"
          } ${popupAlignment}`}
        >
          <div className={horizontalLayout ? "flex gap-5" : ""}>
            <div className="min-w-0 flex-1">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="text-sm font-medium">{format(currentDate, "MMMM yyyy")}</h2>
                <div className="flex gap-0.5">
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    aria-label="Previous month"
                    onClick={() => setCurrentDate((date) => addMonths(date, -1))}
                  >
                    <ChevronLeft />
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    aria-label="Next month"
                    onClick={() => setCurrentDate((date) => addMonths(date, 1))}
                  >
                    <ChevronRight />
                  </Button>
                </div>
              </div>

              <div className="mb-2 grid grid-cols-7 text-center text-xs uppercase text-muted-foreground">
                {"MTWTFSS".split("").map((day, index) => (
                  <div key={`${day}-${index}`}>{day}</div>
                ))}
              </div>

              <div className="grid grid-cols-7 gap-y-2">
                {days.map((day) => {
                  const allowed = isAllowedDate(day);
                  const isStart = Boolean(value?.start && isSameDay(day, value.start));
                  const isEnd = Boolean(value?.end && isSameDay(day, value.end));
                  const currentHover = Boolean(hoverDate && isSelecting && isSameDay(day, hoverDate));
                  const isInRange = Boolean(
                    value?.start &&
                      ((value.end && isWithinInterval(day, { start: value.start, end: value.end })) ||
                        (hoverDate && isWithinInterval(day, { start: value.start, end: hoverDate }))),
                  );

                  return (
                    <button
                      key={day.toString()}
                      type="button"
                      disabled={!allowed}
                      onMouseEnter={() => value?.start && !value.end && setHoverDate(day)}
                      onClick={() => handleDateClick(day)}
                      className={`flex h-8 items-center justify-center rounded text-center text-sm transition-colors ${
                        isInRange && !isStart && !isEnd && !currentHover ? "bg-muted" : ""
                      } ${!isSameMonth(day, currentDate) ? "text-muted-foreground" : ""} ${
                        !allowed ? "cursor-not-allowed opacity-50" : "hover:bg-accent"
                      }`}
                    >
                      <span
                        className={`flex size-8 items-center justify-center rounded ${
                          (isStart || isEnd || currentHover) && allowed
                            ? "bg-primary text-primary-foreground"
                            : isToday(day) && allowed
                              ? "border border-primary text-primary"
                              : ""
                        }`}
                      >
                        {format(day, "d")}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className={horizontalLayout ? "flex flex-col justify-between" : "-mx-3 mt-3 border-t border-border px-3 pt-2.5"}>
              <div className="flex flex-col gap-2">
                <div>
                  <div className="mb-1 text-[13px] text-muted-foreground">Start</div>
                  <div className="grid grid-cols-3 gap-2">
                    <Input
                      value={startDate}
                      onChange={(event) => setStartDate(event.target.value)}
                      aria-label="Start date"
                      aria-invalid={dateError}
                      className={showTimeInput ? "col-span-2" : "col-span-3"}
                    />
                    {showTimeInput && (
                      <Input value={startTime} onChange={(event) => setStartTime(event.target.value)} aria-label="Start time" aria-invalid={timeError} />
                    )}
                  </div>
                </div>
                <div>
                  <div className="mb-1 text-[13px] text-muted-foreground">End</div>
                  <div className="grid grid-cols-3 gap-2">
                    <Input
                      value={endDate}
                      onChange={(event) => setEndDate(event.target.value)}
                      aria-label="End date"
                      aria-invalid={dateError}
                      className={showTimeInput ? "col-span-2" : "col-span-3"}
                    />
                    {showTimeInput && (
                      <Input value={endTime} onChange={(event) => setEndTime(event.target.value)} aria-label="End time" aria-invalid={timeError} />
                    )}
                  </div>
                </div>
              </div>

              <div className="mt-2 flex flex-col gap-2">
                <Button type="button" onClick={handleApply} className="w-full">
                  Apply <span className="text-xs">↵</span>
                </Button>
                <Select value={selectedTimezone} onValueChange={setSelectedTimezone}>
                  <SelectTrigger className="mx-auto w-fit border-0 bg-transparent shadow-none">
                    <Clock3 className="size-3.5" />
                    <span>{timezoneOptions.find((option) => option.value === selectedTimezone)?.label ?? selectedTimezone}</span>
                  </SelectTrigger>
                  <SelectContent>
                    {timezoneOptions.map((option) => (
                      <SelectItem key={option.value} value={option.value}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>

          {Object.keys(availablePresets).length > 0 && presets && (
            <div className="mt-3 flex flex-wrap gap-1 border-t border-border pt-3">
              {Object.entries(availablePresets).map(([key, preset]) => (
                <Button
                  key={key}
                  type="button"
                  variant="ghost"
                  size="xs"
                  onClick={() => {
                    onChange({ start: preset.start, end: preset.end });
                    setIsOpen(false);
                  }}
                >
                  {preset.text}
                </Button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export function DateRangeCalendarDemo() {
  const [date, setDate] = useState<RangeValue | null>(null);

  return (
    <div className="flex min-h-[520px] items-start justify-center p-8">
      <DateRangeCalendar allowClear onChange={setDate} value={date} />
    </div>
  );
}
