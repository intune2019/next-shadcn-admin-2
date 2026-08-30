import Link from "next/link";

import { ArrowRight, ArrowUpRight, Check, Command, Layers3, LineChart, ShieldCheck } from "lucide-react";

import { ThemeSwitcher } from "@/app/(main)/dashboard/_components/header/theme-switcher";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

import { Component as NetworkGlobe } from "./network-globe";

export default function Home() {
  return (
    <main className="min-h-svh overflow-hidden bg-background text-foreground">
      <header className="sticky top-0 z-20 border-border/60 border-b bg-background/80 backdrop-blur">
        <div className="mx-auto flex h-16 w-full max-w-7xl items-center justify-between px-6 lg:px-8">
          <Link href="/" className="flex items-center gap-2.5">
            <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <Command className="size-4" />
            </span>
            <span className="font-heading font-semibold tracking-tight">H.E.O.S.</span>
          </Link>

          <nav className="hidden items-center gap-6 text-muted-foreground text-sm md:flex">
            <Link className="transition-colors hover:text-foreground" href="#capabilities">
              Platform
            </Link>
            <Link className="transition-colors hover:text-foreground" href="#workflow">
              Security
            </Link>
          </nav>

          <div className="flex items-center gap-2">
            <ThemeSwitcher />
            <Button asChild size="sm">
              <Link href="/dashboard/default">
                Request a demo
                <ArrowUpRight />
              </Link>
            </Button>
          </div>
        </div>
      </header>

      <section className="border-border/60 border-b">
        <div className="mx-auto grid w-full max-w-7xl gap-12 px-6 py-16 md:py-24 lg:grid-cols-[1fr_0.9fr] lg:items-center lg:gap-20 lg:px-8 lg:py-28">
          <div className="max-w-2xl">
            <Badge variant="outline" className="my-1.5 -mr-[63px] -ml-[63px] justify-end gap-2 px-3.5 py-6 text-xl">
              <span className="size-1.5 rounded-full bg-primary" />
              EVERY PART OF HEALTCARE
            </Badge>
            <h1 className="mt-6 -ml-[67px] max-w-xl font-heading font-semibold text-[148px] tracking-tight">
              <span className="text-primary">UNIFIED</span>
            </h1>
            <p className="mt-6 max-w-xl text-lg text-muted-foreground leading-8">
              H.E.O.S. is the central nervous system for healthcare organizations of every size; replacing your EHR,
              practice management, and revenue cycle tools with one autonomous, predictive platform.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Button asChild size="lg">
                <Link href="/dashboard/default">
                  Request a demo
                  <ArrowRight />
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline">
                <Link href="#capabilities">Explore the platform</Link>
              </Button>
            </div>
            <div className="mt-6 flex flex-wrap gap-x-5 gap-y-2 text-muted-foreground text-sm">
              <span className="inline-flex items-center gap-2">
                <Check className="size-4 text-primary" />
                One intelligent platform
              </span>
              <span className="inline-flex items-center gap-2">
                <Check className="size-4 text-primary" />
                Built for every part of care
              </span>
            </div>
          </div>

          <div className="relative min-h-[430px] overflow-hidden rounded-xl border border-border/60 bg-background shadow-lg">
            <div className="pointer-events-none absolute inset-0 bg-linear-to-br from-primary/5 via-transparent to-primary/10" />
            <div className="absolute top-6 left-6 z-10">
              <Badge variant="secondary" className="gap-2">
                <span className="size-1.5 rounded-full bg-primary" />
                All systems operational
              </Badge>
            </div>
            <div className="absolute inset-y-0 right-[-14%] flex w-[78%] items-center justify-center">
              <NetworkGlobe size={520} className="max-w-none" />
            </div>
            <div className="absolute right-6 bottom-6 left-6 z-10 flex items-end justify-between gap-4 border-border/60 border-t pt-4">
              <div>
                <p className="font-medium text-sm">Global edge network</p>
                <p className="mt-1 text-muted-foreground text-xs">Connected intelligence across every care setting</p>
              </div>
              <Badge variant="outline">150+ nodes</Badge>
            </div>
          </div>
        </div>
      </section>

      <section id="capabilities" className="mx-auto w-full max-w-7xl px-6 py-20 lg:px-8 lg:py-28">
        <div className="max-w-2xl">
          <p className="font-medium text-primary text-sm uppercase tracking-[0.18em]">One platform, every function</p>
          <h2 className="mt-3 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
            Replace a dozen point solutions with one intelligence layer.
          </h2>
          <p className="mt-4 text-lg text-muted-foreground leading-8">
            One connected platform for the clinical, financial, and operational work that keeps healthcare moving.
          </p>
        </div>

        <div className="mt-12 grid gap-4 md:grid-cols-3">
          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <LineChart className="size-5" />
              </div>
              <CardTitle>Universal Patient Record</CardTitle>
              <CardDescription>
                One globally unique patient identity across every hospital, clinic, pharmacy, and carrier. No
                duplicates. No faxing.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                Identity across every care setting
              </div>
            </CardContent>
          </Card>

          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <Layers3 className="size-5" />
              </div>
              <CardTitle>Autonomous Documentation</CardTitle>
              <CardDescription>
                AI listens during visits and drafts SOAP notes, H&amp;P, referrals, and orders in real time. Providers
                approve—never type.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                More time for patients
              </div>
            </CardContent>
          </Card>

          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <ShieldCheck className="size-5" />
              </div>
              <CardTitle>Revenue Cycle, Automated</CardTitle>
              <CardDescription>
                Eligibility, coding, claim scrubbing, denial management, and payment posting—end to end, with zero
                manual intervention.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                From eligibility to payment
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section id="workflow" className="border-border/60 border-y bg-muted/20">
        <div className="mx-auto grid w-full max-w-7xl gap-12 px-6 py-20 lg:grid-cols-[0.8fr_1.2fr] lg:items-center lg:px-8 lg:py-24">
          <div>
            <Badge variant="secondary">Revenue cycle</Badge>
            <h2 className="mt-4 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
              Zero manual intervention, from eligibility to payment.
            </h2>
            <p className="mt-4 max-w-lg text-lg text-muted-foreground leading-8">
              Insurance verification, coding, claim scrubbing, denial management, and payment posting all run
              automatically—with AI explaining every code it recommends.
            </p>
            <Button asChild className="mt-8" variant="outline">
              <Link href="/dashboard/default">
                Explore the platform
                <ArrowRight />
              </Link>
            </Button>
          </div>

          <div className="grid gap-4 sm:grid-cols-3">
            <Card>
              <CardContent className="pt-6">
                <div className="flex size-9 items-center justify-center rounded-full bg-primary font-medium text-primary-foreground text-sm">
                  01
                </div>
                <h3 className="mt-5 font-medium uppercase tracking-wide">Before visit</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Insurance verification
                  <br />
                  Eligibility checks
                  <br />
                  Prior authorization
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <div className="flex size-9 items-center justify-center rounded-full bg-primary font-medium text-primary-foreground text-sm">
                  02
                </div>
                <h3 className="mt-5 font-medium uppercase tracking-wide">During visit</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Coding recommendation
                  <br />
                  HCC capture
                  <br />
                  Risk adjustment
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <div className="flex size-9 items-center justify-center rounded-full bg-primary font-medium text-primary-foreground text-sm">
                  03
                </div>
                <h3 className="mt-5 font-medium uppercase tracking-wide">After visit</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Claim generation &amp; scrubbing
                  <br />
                  Submission &amp; follow-up
                  <br />
                  Denial management
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      <section className="mx-auto w-full max-w-7xl px-6 py-20 lg:px-8 lg:py-28">
        <Card className="overflow-hidden bg-primary text-primary-foreground shadow-lg">
          <div className="grid gap-8 p-8 sm:p-10 lg:grid-cols-[1fr_auto] lg:items-center lg:p-12">
            <div className="max-w-2xl">
              <p className="font-medium text-primary-foreground/70 text-sm uppercase tracking-[0.18em]">Not an EHR</p>
              <h2 className="mt-3 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
                The operating system for humanity&apos;s healthcare.
              </h2>
              <p className="mt-4 max-w-xl text-lg text-primary-foreground/75 leading-8">
                Frictionless for patients. Effortless for providers. Predictable for executives. Interoperable for the
                ecosystem.
              </p>
            </div>
            <Button asChild size="lg" variant="secondary">
              <Link href="/dashboard/default">
                Request a demo
                <ArrowUpRight />
              </Link>
            </Button>
          </div>
        </Card>
      </section>

      <footer className="border-border/60 border-t">
        <div className="mx-auto flex w-full max-w-7xl flex-col gap-3 px-6 py-8 text-muted-foreground text-sm sm:flex-row sm:items-center sm:justify-between lg:px-8">
          <div className="flex items-center gap-2">
            <Command className="size-4" />
            <span>H.E.O.S.</span>
          </div>
          <p>The Healthcare Operating System for humanity&apos;s healthcare.</p>
        </div>
      </footer>
    </main>
  );
}
