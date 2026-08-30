import Link from "next/link";

import { ArrowRight, ArrowUpRight, Check, Command, Layers3, LineChart, ShieldCheck } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function Home() {
  return (
    <main className="min-h-svh overflow-hidden bg-background text-foreground">
      <header className="sticky top-0 z-20 border-border/60 border-b bg-background/80 backdrop-blur">
        <div className="mx-auto flex h-16 w-full max-w-7xl items-center justify-between px-6 lg:px-8">
          <Link href="/" className="flex items-center gap-2.5">
            <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <Command className="size-4" />
            </span>
            <span className="font-heading font-semibold tracking-tight">Studio Admin</span>
          </Link>

          <nav className="hidden items-center gap-6 text-muted-foreground text-sm md:flex">
            <Link className="transition-colors hover:text-foreground" href="#capabilities">
              Capabilities
            </Link>
            <Link className="transition-colors hover:text-foreground" href="#workflow">
              Workflow
            </Link>
          </nav>

          <Button asChild size="sm">
            <Link href="/dashboard/default">
              Open dashboard
              <ArrowUpRight />
            </Link>
          </Button>
        </div>
      </header>

      <section className="border-border/60 border-b">
        <div className="mx-auto grid w-full max-w-7xl gap-12 px-6 py-16 md:py-24 lg:grid-cols-[1fr_0.9fr] lg:items-center lg:gap-20 lg:px-8 lg:py-28">
          <div className="max-w-2xl">
            <Badge variant="outline" className="gap-2 px-3 py-1">
              <span className="size-1.5 rounded-full bg-primary" />A calmer way to run the workday
            </Badge>
            <h1 className="mt-6 max-w-xl font-heading font-semibold text-4xl tracking-tight sm:text-5xl lg:text-6xl">
              See the work clearly. Move it forward.
            </h1>
            <p className="mt-6 max-w-xl text-lg text-muted-foreground leading-8">
              Studio Admin brings your most important activity, customer signals, and team priorities into one focused
              workspace.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Button asChild size="lg">
                <Link href="/dashboard/default">
                  Open the dashboard
                  <ArrowRight />
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline">
                <Link href="#capabilities">Explore capabilities</Link>
              </Button>
            </div>
            <div className="mt-6 flex flex-wrap gap-x-5 gap-y-2 text-muted-foreground text-sm">
              <span className="inline-flex items-center gap-2">
                <Check className="size-4 text-primary" />
                One connected workspace
              </span>
              <span className="inline-flex items-center gap-2">
                <Check className="size-4 text-primary" />
                Built for everyday decisions
              </span>
            </div>
          </div>

          <Card className="relative overflow-hidden border-primary/15 bg-linear-to-br from-primary/10 via-card to-card shadow-lg">
            <div className="pointer-events-none absolute -top-24 -right-24 size-56 rounded-full bg-primary/10 blur-3xl" />
            <CardHeader className="relative border-border/60 border-b pb-4">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <CardDescription>Workspace snapshot</CardDescription>
                  <CardTitle className="mt-1 text-xl">Good morning, team</CardTitle>
                </div>
                <Badge variant="secondary">Live view</Badge>
              </div>
            </CardHeader>
            <CardContent className="relative space-y-5 pt-5">
              <div className="grid grid-cols-3 gap-3">
                <div className="rounded-lg border bg-background/70 p-3">
                  <p className="text-muted-foreground text-xs">Active accounts</p>
                  <p className="mt-2 font-medium text-2xl tracking-tight">45,678</p>
                  <p className="mt-1 text-muted-foreground text-xs">+12.5% this month</p>
                </div>
                <div className="rounded-lg border bg-background/70 p-3">
                  <p className="text-muted-foreground text-xs">New customers</p>
                  <p className="mt-2 font-medium text-2xl tracking-tight">1,234</p>
                  <p className="mt-1 text-muted-foreground text-xs">This quarter</p>
                </div>
                <div className="rounded-lg border bg-background/70 p-3">
                  <p className="text-muted-foreground text-xs">Growth rate</p>
                  <p className="mt-2 font-medium text-2xl tracking-tight">4.5%</p>
                  <p className="mt-1 text-muted-foreground text-xs">On target</p>
                </div>
              </div>

              <div className="rounded-lg border bg-background/70 p-4">
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <p className="font-medium text-sm">Customer activity</p>
                    <p className="mt-1 text-muted-foreground text-xs">Last 3 months</p>
                  </div>
                  <LineChart className="size-4 text-muted-foreground" />
                </div>
                <div className="mt-5 flex h-24 items-end gap-2">
                  <div className="h-10 flex-1 rounded-sm bg-primary/25" />
                  <div className="h-14 flex-1 rounded-sm bg-primary/35" />
                  <div className="h-12 flex-1 rounded-sm bg-primary/45" />
                  <div className="h-20 flex-1 rounded-sm bg-primary/60" />
                  <div className="h-16 flex-1 rounded-sm bg-primary/70" />
                  <div className="h-24 flex-1 rounded-sm bg-primary" />
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section id="capabilities" className="mx-auto w-full max-w-7xl px-6 py-20 lg:px-8 lg:py-28">
        <div className="max-w-2xl">
          <p className="font-medium text-primary text-sm uppercase tracking-[0.18em]">Everything in view</p>
          <h2 className="mt-3 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
            A focused home for the signals that matter.
          </h2>
          <p className="mt-4 text-lg text-muted-foreground leading-8">
            Start with the overview, then move into the detail you need. The dashboard keeps your team aligned without
            adding noise.
          </p>
        </div>

        <div className="mt-12 grid gap-4 md:grid-cols-3">
          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <LineChart className="size-5" />
              </div>
              <CardTitle>Understand momentum</CardTitle>
              <CardDescription>See the trends behind your activity and spot meaningful changes early.</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                Performance at a glance
              </div>
            </CardContent>
          </Card>

          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <Layers3 className="size-5" />
              </div>
              <CardTitle>Keep context close</CardTitle>
              <CardDescription>
                Bring customer records, status, and recent activity together in one place.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                Less searching, more doing
              </div>
            </CardContent>
          </Card>

          <Card className="bg-linear-to-b from-primary/5 to-card shadow-xs">
            <CardHeader>
              <div className="mb-3 flex size-10 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <ShieldCheck className="size-5" />
              </div>
              <CardTitle>Make confident calls</CardTitle>
              <CardDescription>
                Use a consistent view of the work to turn updates into clear next steps.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Check className="size-4 text-primary" />
                Designed for clarity
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <section id="workflow" className="border-border/60 border-y bg-muted/20">
        <div className="mx-auto grid w-full max-w-7xl gap-12 px-6 py-20 lg:grid-cols-[0.8fr_1.2fr] lg:items-center lg:px-8 lg:py-24">
          <div>
            <Badge variant="secondary">From overview to action</Badge>
            <h2 className="mt-4 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
              Start broad. Go deeper when it counts.
            </h2>
            <p className="mt-4 max-w-lg text-lg text-muted-foreground leading-8">
              The public site is your front door. The dashboard is where the day gets done. Move between both without
              losing your place.
            </p>
            <Button asChild className="mt-8" variant="outline">
              <Link href="/dashboard/default">
                Enter the workspace
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
                <h3 className="mt-5 font-medium">Orient</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Open with the signals that deserve attention today.
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <div className="flex size-9 items-center justify-center rounded-full bg-primary font-medium text-primary-foreground text-sm">
                  02
                </div>
                <h3 className="mt-5 font-medium">Explore</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Follow the detail behind a trend, account, or update.
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <div className="flex size-9 items-center justify-center rounded-full bg-primary font-medium text-primary-foreground text-sm">
                  03
                </div>
                <h3 className="mt-5 font-medium">Act</h3>
                <p className="mt-2 text-muted-foreground text-sm leading-6">
                  Turn a clear view into the next useful decision.
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
              <p className="font-medium text-primary-foreground/70 text-sm uppercase tracking-[0.18em]">
                Your next view starts here
              </p>
              <h2 className="mt-3 font-heading font-semibold text-3xl tracking-tight sm:text-4xl">
                Bring the whole picture into focus.
              </h2>
              <p className="mt-4 max-w-xl text-lg text-primary-foreground/75 leading-8">
                Open the dashboard and make the next decision with the context already in front of you.
              </p>
            </div>
            <Button asChild size="lg" variant="secondary">
              <Link href="/dashboard/default">
                Open dashboard
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
            <span>Studio Admin</span>
          </div>
          <p>Keep the important work moving.</p>
        </div>
      </footer>
    </main>
  );
}
