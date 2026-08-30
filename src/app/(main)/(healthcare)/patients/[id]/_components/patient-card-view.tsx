"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowLeft, BadgeCheck, CalendarDays, ClipboardCheck, ClipboardList, ShieldCheck, Stethoscope } from "lucide-react";

import { Calendar } from "@/app/(main)/dashboard/calendar/_components/calendar";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldGroup, FieldLabel, FieldLegend, FieldSet, FieldTitle } from "@/components/ui/field";
import { Progress } from "@/components/ui/progress";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Separator } from "@/components/ui/separator";
import { Textarea } from "@/components/ui/textarea";

import type { PatientCardView as PatientCardViewName } from "./data";
import { getPatientProfile } from "./data";

const viewLinks: Array<{ value: PatientCardViewName; label: string; icon: typeof CalendarDays }> = [
  { value: "front-desk", label: "Front desk", icon: CalendarDays },
  { value: "back-office", label: "Back office", icon: ClipboardList },
  { value: "preventive", label: "Preventive questions", icon: ClipboardCheck },
];

export function PatientCardView({ patientId, view }: { patientId: string; view: PatientCardViewName }) {
  const patient = getPatientProfile(patientId);

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex min-w-0 items-center gap-3">
          <Button asChild size="icon-sm" variant="ghost">
            <Link href="/patients" aria-label="Back to patients">
              <ArrowLeft />
            </Link>
          </Button>
          <Avatar size="lg">
            <AvatarFallback>{patient.initials}</AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="truncate text-2xl tracking-tight">{patient.name}</h1>
              <Badge variant="secondary">Patient card</Badge>
            </div>
            <p className="text-muted-foreground text-sm">
              {patient.mrn} · {patient.dob} · {patient.age === null ? "Age not on file" : `${patient.age} years`} · {patient.careTeam}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2 pl-12 lg:pl-0">
          <Button asChild size="sm" variant="outline">
            <Link href={`/patients/${patient.id}/timeline`}>
              <ShieldCheck data-icon="inline-start" />
              Timeline
            </Link>
          </Button>
          <Button asChild size="sm">
            <Link href={`/patients/${patient.id}/encounters`}>
              <Stethoscope data-icon="inline-start" />
              Open encounter
            </Link>
          </Button>
        </div>
      </div>

      <Card size="sm">
        <CardHeader className="gap-3 border-b">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle>Patient workflow</CardTitle>
              <CardDescription>Move from arrival through chart readiness and preventive review.</CardDescription>
            </div>
            <Badge variant="outline">
              <BadgeCheck data-icon="inline-start" />
              Identity verified
            </Badge>
          </div>
          <nav aria-label="Patient workflow views" className="flex flex-wrap gap-2">
            {viewLinks.map((item) => {
              const Icon = item.icon;
              const href = `/patients/${patient.id}/${item.value}`;

              return (
                <Button asChild key={item.value} size="sm" variant={view === item.value ? "default" : "outline"}>
                  <Link href={href} aria-current={view === item.value ? "page" : undefined}>
                    <Icon data-icon="inline-start" />
                    {item.label}
                  </Link>
                </Button>
              );
            })}
          </nav>
        </CardHeader>
        <CardContent className="pt-4">
          <div className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
            <div className="flex items-center gap-2">
              <CalendarDays className="size-4 text-muted-foreground" />
              <span className="text-muted-foreground">Today&apos;s visit</span>
              <span className="font-medium">9:30 AM</span>
            </div>
            <div className="flex items-center gap-2">
              <Stethoscope className="size-4 text-muted-foreground" />
              <span className="text-muted-foreground">Provider</span>
              <span className="font-medium">{patient.primaryProvider}</span>
            </div>
            <div className="flex items-center gap-2">
              <ShieldCheck className="size-4 text-muted-foreground" />
              <span className="text-muted-foreground">Coverage</span>
              <span className="truncate font-medium">{patient.insurance}</span>
            </div>
          </div>
        </CardContent>
      </Card>

      <Separator />

      {view === "front-desk" ? <FrontDeskView patient={patient} /> : null}
      {view === "back-office" ? <BackOfficeView patient={patient} /> : null}
      {view === "preventive" ? <PreventiveView patient={patient} /> : null}
    </div>
  );
}

function FrontDeskView({ patient }: { patient: ReturnType<typeof getPatientProfile> }) {
  const [patientFlags, setPatientFlags] = React.useState({ sex: true, race: true, eligibility: false, telehealth: false });
  const metrics = [
    { label: "Patients scheduled", value: "18", detail: "4 remaining today" },
    { label: "Patients rescheduled", value: "2", detail: "1 needs outreach" },
    { label: "Cancellations", value: "1", detail: "Updated 8 minutes ago" },
    { label: "Patients seen", value: "7", detail: "39% of today's visits" },
    { label: "Doctors in clinic", value: "4", detail: "Across 2 locations" },
  ];

  return (
    <div className="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-3">
      <div className="flex min-w-0 flex-col gap-4 xl:col-span-2">
        <div className="grid grid-cols-2 gap-4 xl:grid-cols-5">
          {metrics.map((metric) => (
            <Card key={metric.label} size="sm">
              <CardHeader>
                <CardDescription>{metric.label}</CardDescription>
              </CardHeader>
              <CardContent>
                <p className="text-2xl leading-none tracking-tight">{metric.value}</p>
                <p className="mt-2 text-muted-foreground text-xs">{metric.detail}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Schedule</CardTitle>
            <CardDescription>Today&apos;s appointments and arrival status for {patient.location}.</CardDescription>
          </CardHeader>
          <CardContent className="px-0">
            <Calendar />
          </CardContent>
        </Card>
      </div>

      <aside className="flex min-w-0 flex-col gap-4">
        <Card>
          <CardHeader>
            <CardTitle>Patient information</CardTitle>
            <CardDescription>Confirm registration details before rooming.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div className="flex items-center gap-3">
              <Avatar>
                <AvatarFallback>{patient.initials}</AvatarFallback>
              </Avatar>
              <div className="min-w-0">
                <p className="font-medium">{patient.name}</p>
                <p className="text-muted-foreground text-sm">{patient.mrn}</p>
              </div>
            </div>
            <dl className="flex flex-col gap-3 text-sm">
              <div className="flex items-start justify-between gap-3">
                <dt className="text-muted-foreground">Address</dt>
                <dd className="text-right font-medium">Northstar neighborhood</dd>
              </div>
              <div className="flex items-start justify-between gap-3">
                <dt className="text-muted-foreground">Phone</dt>
                <dd className="text-right font-medium">{patient.phone}</dd>
              </div>
              <div className="flex items-start justify-between gap-3">
                <dt className="text-muted-foreground">Emergency contact</dt>
                <dd className="max-w-40 text-right font-medium">{patient.emergencyContact}</dd>
              </div>
            </dl>
            <FieldGroup className="grid grid-cols-2 gap-3 border-t pt-4">
              {(
                [
                  ["sex", "Sex"],
                  ["race", "Race"],
                  ["eligibility", "Eligibility check"],
                  ["telehealth", "Telehealth"],
                ] as const
              ).map(([key, label]) => (
                <Field key={key} orientation="horizontal">
                  <Checkbox
                    checked={patientFlags[key]}
                    id={`front-desk-${key}`}
                    onCheckedChange={(checked) => setPatientFlags((current) => ({ ...current, [key]: checked === true }))}
                  />
                  <FieldLabel htmlFor={`front-desk-${key}`}>{label}</FieldLabel>
                </Field>
              ))}
            </FieldGroup>
            <Field className="border-t pt-4">
              <FieldLabel htmlFor="front-desk-notes">Additional notes</FieldLabel>
              <Textarea id="front-desk-notes" placeholder="Add a registration note" />
            </Field>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Quick actions</CardTitle>
            <CardDescription>Common front-desk actions for this visit.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-2">
            <Button className="justify-start" variant="outline">
              <CalendarDays data-icon="inline-start" />
              Reschedule appointment
            </Button>
            <Button className="justify-start" variant="outline">
              <ClipboardCheck data-icon="inline-start" />
              Verify coverage
            </Button>
            <Button className="justify-start" variant="outline">
              <ShieldCheck data-icon="inline-start" />
              Open consent forms
            </Button>
          </CardContent>
        </Card>
      </aside>
    </div>
  );
}

function BackOfficeView({ patient }: { patient: ReturnType<typeof getPatientProfile> }) {
  const [prepared, setPrepared] = React.useState(false);
  const chartProgress = prepared ? 100 : 72;

  return (
    <div className="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-3">
      <div className="flex min-w-0 flex-col gap-4 xl:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle>Chart preparation</CardTitle>
            <CardDescription>Review the patient record before the provider begins the encounter.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-5">
            <div className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
              <div className="flex flex-col gap-1">
                <span className="text-muted-foreground">Patient</span>
                <span className="font-medium">{patient.name}</span>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-muted-foreground">DOB</span>
                <span className="font-medium">{patient.dob}</span>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-muted-foreground">Sex</span>
                <span className="font-medium">{patient.sex}</span>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-muted-foreground">Primary diagnosis</span>
                <span className="font-medium">{patient.diagnosis}</span>
              </div>
            </div>
            <div className="flex flex-col gap-2 border-t pt-4">
              <div className="flex items-center justify-between gap-3 text-sm">
                <span className="font-medium" id="chart-completion-label">
                  Chart preparation — {chartProgress}%
                </span>
                <Badge variant={prepared ? "default" : "secondary"}>{prepared ? "Ready" : "In progress"}</Badge>
              </div>
              <Progress aria-labelledby="chart-completion-label" value={chartProgress} />
            </div>
            <div className="grid grid-cols-1 gap-3 border-t pt-4 md:grid-cols-2">
              <Card size="sm">
                <CardHeader>
                  <CardTitle className="text-sm">Medication list</CardTitle>
                  <CardDescription>Reconcile with the patient at every transition.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-2 text-sm">
                  <p>Metformin 500 mg · twice daily</p>
                  <p>Lisinopril 10 mg · once daily</p>
                  <Badge className="w-fit" variant="outline">
                    Patient confirmation needed
                  </Badge>
                </CardContent>
              </Card>
              <Card size="sm">
                <CardHeader>
                  <CardTitle className="text-sm">Allergies</CardTitle>
                  <CardDescription>Confirm reaction and severity.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-2 text-sm">
                  <p>Penicillin · rash</p>
                  <p>No other known drug allergies</p>
                  <Badge className="w-fit" variant="outline">
                    Reviewed May 2, 2025
                  </Badge>
                </CardContent>
              </Card>
            </div>
            <Button className="w-full sm:w-fit" onClick={() => setPrepared(true)}>
              <ClipboardCheck data-icon="inline-start" />
              {prepared ? "Chart marked ready" : "Mark chart prepared"}
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Vitals</CardTitle>
            <CardDescription>Capture current measurements during rooming.</CardDescription>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-4 md:grid-cols-4">
            {[
              ["BP", "128 / 78", "mmHg"],
              ["Pulse", "74", "bpm"],
              ["O₂", "98", "%"],
              ["Weight", "162", "lb"],
              ["Height", "66", "in"],
              ["Temp", "98.4", "°F"],
              ["Pain", "2", "/ 10"],
            ].map(([label, value, unit]) => (
              <div className="flex flex-col gap-1" key={label}>
                <span className="text-muted-foreground text-xs">{label}</span>
                <div className="flex items-baseline gap-1">
                  <span className="font-medium text-lg">{value}</span>
                  <span className="text-muted-foreground text-xs">{unit}</span>
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      <aside className="flex min-w-0 flex-col gap-4">
        <Card>
          <CardHeader>
            <CardTitle>Results and orders</CardTitle>
            <CardDescription>Close the loop on clinical work before the visit.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            {[
              ["Labs", "2 results to review", "4 days ago", "secondary"],
              ["Incomplete results", "1 result needs follow-up", "Needs attention", "destructive"],
              ["Doctor orders", "3 open orders", "Updated today", "outline"],
            ].map(([title, detail, meta, variant]) => (
              <div className="flex items-center justify-between gap-3 rounded-lg border p-3" key={title}>
                <div className="min-w-0">
                  <p className="font-medium text-sm">{title}</p>
                  <p className="truncate text-muted-foreground text-xs">{detail}</p>
                </div>
                <Badge variant={variant as "default" | "destructive" | "outline" | "secondary"}>{meta}</Badge>
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Immunizations</CardTitle>
            <CardDescription>Compare the record with the current adult schedule.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <div className="flex items-center justify-between gap-3 text-sm">
              <span>Influenza</span>
              <Badge variant="default">Current</Badge>
            </div>
            <div className="flex items-center justify-between gap-3 text-sm">
              <span>COVID-19</span>
              <Badge variant="secondary">Verify</Badge>
            </div>
            <div className="flex items-center justify-between gap-3 text-sm">
              <span>Tdap</span>
              <Badge variant="outline">Due 2026</Badge>
            </div>
            <Button asChild className="mt-1 w-full" variant="outline">
              <a href="https://www.cdc.gov/vaccines/hcp/imz-schedules/adult.html" rel="noreferrer" target="_blank">
                View CDC adult schedule
              </a>
            </Button>
          </CardContent>
        </Card>
      </aside>
    </div>
  );
}

function PreventiveView({ patient }: { patient: ReturnType<typeof getPatientProfile> }) {
  type YesNoUnknown = "yes" | "no" | "unknown";
  const [answers, setAnswers] = React.useState<Record<string, YesNoUnknown>>({
    allergies: "yes",
    hospitalizations: "no",
    tobacco: "no",
    alcohol: "no",
    drugs: "no",
    phq2: "no",
    memory: "unknown",
  });
  const [saved, setSaved] = React.useState(false);

  function updateAnswer(key: string, value: string) {
    setAnswers((current) => ({ ...current, [key]: value as YesNoUnknown }));
    setSaved(false);
  }

  return (
    <div className="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-3">
      <Card className="xl:col-span-2">
        <CardHeader>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <CardTitle>Preventive questions</CardTitle>
              <CardDescription>Structured screening for {patient.name} before the provider review.</CardDescription>
            </div>
            <Badge variant={saved ? "default" : "secondary"}>{saved ? "Saved just now" : "Not saved"}</Badge>
          </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-6">
          <FieldSet>
            <FieldLegend>Patient history</FieldLegend>
            <FieldGroup className="grid gap-5 md:grid-cols-2">
              <RadioQuestion
                id="allergies"
                label="Allergies to any medications?"
                value={answers.allergies}
                onChange={(value) => updateAnswer("allergies", value)}
              />
              <RadioQuestion
                id="hospitalizations"
                label="Any hospitalizations in the last 30 days or since last visit?"
                value={answers.hospitalizations}
                onChange={(value) => updateAnswer("hospitalizations", value)}
              />
            </FieldGroup>
          </FieldSet>

          <FieldSet className="border-t pt-5">
            <FieldLegend>Social history</FieldLegend>
            <FieldGroup className="grid gap-5 md:grid-cols-3">
              <RadioQuestion
                id="tobacco"
                label="Tobacco or vaping?"
                value={answers.tobacco}
                onChange={(value) => updateAnswer("tobacco", value)}
              />
              <RadioQuestion
                id="alcohol"
                label="Alcohol use?"
                value={answers.alcohol}
                onChange={(value) => updateAnswer("alcohol", value)}
              />
              <RadioQuestion
                id="drugs"
                label="Non-prescribed drugs?"
                value={answers.drugs}
                onChange={(value) => updateAnswer("drugs", value)}
              />
            </FieldGroup>
          </FieldSet>

          <FieldSet className="border-t pt-5">
            <FieldLegend>Preventive assessments</FieldLegend>
            <FieldGroup className="grid gap-5 md:grid-cols-2">
              <RadioQuestion
                id="phq2"
                label="PHQ-2: felt down, depressed, or hopeless?"
                value={answers.phq2}
                onChange={(value) => updateAnswer("phq2", value)}
              />
              <RadioQuestion
                id="memory"
                label="Memory concern or change since last visit?"
                value={answers.memory}
                onChange={(value) => updateAnswer("memory", value)}
              />
            </FieldGroup>
          </FieldSet>

          <Field className="border-t pt-5">
            <FieldLabel htmlFor="preventive-notes">Assessment notes</FieldLabel>
            <Textarea id="preventive-notes" placeholder="Add context for the provider review" />
          </Field>

          <Button className="w-full sm:w-fit" onClick={() => setSaved(true)}>
            <ClipboardCheck data-icon="inline-start" />
            Save assessment
          </Button>
        </CardContent>
      </Card>

      <aside className="flex min-w-0 flex-col gap-4">
        <Card>
          <CardHeader>
            <CardTitle>Assessment progress</CardTitle>
            <CardDescription>Complete the intake before the provider signs the encounter.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div className="flex items-end justify-between gap-3">
              <span className="text-3xl leading-none tracking-tight">7 / 8</span>
              <Badge variant="secondary">In progress</Badge>
            </div>
            <Progress aria-label="Preventive assessment completion" value={88} />
            <p className="text-muted-foreground text-sm">One response is marked unknown and needs confirmation.</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Evidence-based guidance</CardTitle>
            <CardDescription>Use current sources to support the clinical conversation.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <div className="rounded-lg border p-3">
              <p className="font-medium text-sm">USPSTF screening recommendations</p>
              <p className="mt-1 text-muted-foreground text-xs">Hypertension and diabetes screening guidance.</p>
              <Button asChild className="mt-2 px-0" size="sm" variant="link">
                <a
                  href="https://www.uspreventiveservicestaskforce.org/uspstf/recommendation/hypertension-in-adults-screening"
                  rel="noreferrer"
                  target="_blank"
                >
                  Open USPSTF guidance
                </a>
              </Button>
            </div>
            <div className="rounded-lg border p-3">
              <p className="font-medium text-sm">AHRQ medication reconciliation</p>
              <p className="mt-1 text-muted-foreground text-xs">Patient and family engagement for a complete medication list.</p>
              <Button asChild className="mt-2 px-0" size="sm" variant="link">
                <a href="https://www.ahrq.gov/patient-safety/reports/engage/medlist.html" rel="noreferrer" target="_blank">
                  Open AHRQ guidance
                </a>
              </Button>
            </div>
          </CardContent>
        </Card>
      </aside>
    </div>
  );
}

function RadioQuestion({
  id,
  label,
  value,
  onChange,
}: {
  id: string;
  label: string;
  value: "yes" | "no" | "unknown";
  onChange: (value: string) => void;
}) {
  return (
    <Field>
      <FieldTitle>{label}</FieldTitle>
      <RadioGroup aria-label={label} className="grid grid-cols-3 gap-2" onValueChange={onChange} value={value}>
        {[
          ["yes", "Yes"],
          ["no", "No"],
          ["unknown", "Unknown"],
        ].map(([option, optionLabel]) => (
          <Field className="rounded-lg border border-input px-3 py-2 transition-colors hover:bg-muted" key={option} orientation="horizontal">
            <RadioGroupItem id={`${id}-${option}`} value={option} />
            <FieldLabel htmlFor={`${id}-${option}`}>{optionLabel}</FieldLabel>
          </Field>
        ))}
      </RadioGroup>
    </Field>
  );
}
