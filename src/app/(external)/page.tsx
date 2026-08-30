"use client";

import Link from "next/link";

import {
  ArrowRight,
  BarChart3,
  BriefcaseBusiness,
  Circle,
  FileCheck2,
  Landmark,
  Menu,
  Scale,
  ShieldCheck,
  X,
} from "lucide-react";

import { Footer } from "@/components/ui/footer-section";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Button } from "@/components/ui/button";
import {
  NavigationMenu,
  NavigationMenuContent,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  NavigationMenuTrigger,
} from "@/components/ui/navigation-menu";
import { Sheet, SheetClose, SheetContent, SheetTrigger } from "@/components/ui/sheet";

const productLinks = [
  {
    title: "Governance",
    description: "Clear oversight for complex organizations.",
    icon: Scale,
  },
  {
    title: "Compliance",
    description: "Practical control over critical requirements.",
    icon: ShieldCheck,
  },
  {
    title: "Treasury",
    description: "Financial visibility for confident decisions.",
    icon: Landmark,
  },
];

const companyLinks = [
  {
    title: "Our approach",
    description: "Tailored insight for every stage of growth.",
    icon: BriefcaseBusiness,
  },
  {
    title: "Insights",
    description: "Perspectives that turn information into action.",
    icon: BarChart3,
  },
  {
    title: "Trust center",
    description: "Our commitment to security and accountability.",
    icon: FileCheck2,
  },
];

function MenuLink({
  title,
  description,
  icon: Icon,
}: (typeof productLinks)[number]) {
  return (
    <NavigationMenuLink href="#" className="group flex min-w-56 gap-3 p-3">
      <span className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg border bg-muted/20">
        <Icon className="size-4 text-primary" aria-hidden="true" />
      </span>
      <span className="space-y-1">
        <span className="block text-sm font-medium text-foreground">{title}</span>
        <span className="block text-xs leading-5 text-muted-foreground">{description}</span>
      </span>
    </NavigationMenuLink>
  );
}

function DesktopMenu() {
  return (
    <NavigationMenu className="hidden lg:flex">
      <NavigationMenuList>
        <NavigationMenuItem>
          <NavigationMenuTrigger>Product</NavigationMenuTrigger>
          <NavigationMenuContent>
            <ul className="grid w-[22rem] gap-1 p-2 sm:grid-cols-2">
              {productLinks.map((link) => (
                <li key={link.title}>
                  <MenuLink {...link} />
                </li>
              ))}
            </ul>
          </NavigationMenuContent>
        </NavigationMenuItem>
        <NavigationMenuItem>
          <NavigationMenuTrigger>Company</NavigationMenuTrigger>
          <NavigationMenuContent>
            <ul className="grid w-[22rem] gap-1 p-2 sm:grid-cols-2">
              {companyLinks.map((link) => (
                <li key={link.title}>
                  <MenuLink {...link} />
                </li>
              ))}
            </ul>
          </NavigationMenuContent>
        </NavigationMenuItem>
        <NavigationMenuItem>
          <NavigationMenuLink href="#pricing">Pricing</NavigationMenuLink>
        </NavigationMenuItem>
      </NavigationMenuList>
    </NavigationMenu>
  );
}

function MobileMenu() {
  const sections = [
    { id: "product", title: "Product", links: productLinks },
    { id: "company", title: "Company", links: companyLinks },
  ];

  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button size="icon" variant="ghost" className="rounded-full lg:hidden">
          <Menu className="size-5" aria-hidden="true" />
          <span className="sr-only">Open navigation</span>
        </Button>
      </SheetTrigger>
      <SheetContent className="w-full gap-0 bg-background/95 p-0 backdrop-blur-lg" showCloseButton={false}>
        <div className="flex h-14 items-center justify-end border-b px-4">
          <SheetClose asChild>
            <Button size="icon" variant="ghost" className="rounded-full">
              <X className="size-5" aria-hidden="true" />
              <span className="sr-only">Close navigation</span>
            </Button>
          </SheetClose>
        </div>
        <div className="grid gap-y-2 overflow-y-auto px-4 pt-5 pb-12">
          <Accordion type="single" collapsible>
            {sections.map((section) => (
              <AccordionItem key={section.id} value={section.id}>
                <AccordionTrigger className="capitalize hover:no-underline">{section.title}</AccordionTrigger>
                <AccordionContent className="space-y-1">
                  <ul className="grid gap-1">
                    {section.links.map((link) => {
                      const Icon = link.icon;

                      return (
                        <li key={link.title}>
                          <SheetClose asChild>
                            <a href="#" className="flex gap-3 rounded-md p-2 transition-colors hover:bg-muted">
                              <span className="flex size-10 items-center justify-center rounded-lg border bg-muted/20">
                                <Icon className="size-4 text-primary" aria-hidden="true" />
                              </span>
                              <span className="flex h-10 flex-col justify-center">
                                <span className="text-sm">{link.title}</span>
                                <span className="line-clamp-1 text-xs text-muted-foreground">{link.description}</span>
                              </span>
                            </a>
                          </SheetClose>
                        </li>
                      );
                    })}
                  </ul>
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
          <SheetClose asChild>
            <Button asChild className="mt-5">
              <Link href="/dashboard">
                Enter workspace
                <ArrowRight data-icon="inline-end" aria-hidden="true" />
              </Link>
            </Button>
          </SheetClose>
        </div>
      </SheetContent>
    </Sheet>
  );
}

export default function FrontendPage() {
  return (
    <main className="min-h-dvh overflow-hidden bg-[#0D0D0D] text-foreground">
      <div className="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_50%_32%,rgba(52,211,153,0.1),transparent_28%)]" />
      <div className="pointer-events-none fixed inset-0 opacity-40 [background-image:linear-gradient(rgba(255,255,255,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.025)_1px,transparent_1px)] [background-size:72px_72px] [mask-image:radial-gradient(ellipse_at_center,black,transparent_78%)]" />

      <div className="relative mx-auto flex min-h-dvh w-full max-w-[1440px] flex-col px-4 py-4 sm:px-8 sm:py-6 lg:px-14">
        <header className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between rounded-lg border bg-background/80 px-4 backdrop-blur-xl">
          <Link href="/frontend" className="flex items-center gap-2">
            <Circle className="size-5 fill-primary text-primary" aria-hidden="true" />
            <span className="font-mono text-base font-bold">In.Tune &amp; Associates</span>
          </Link>
          <DesktopMenu />
          <div className="flex items-center gap-2">
            <Button asChild className="hidden sm:inline-flex">
              <Link href="/dashboard">
                Get Started
                <ArrowRight data-icon="inline-end" aria-hidden="true" />
              </Link>
            </Button>
            <MobileMenu />
          </div>
        </header>

        <section className="mx-auto flex w-full max-w-6xl flex-1 flex-col items-center justify-center py-20 text-center sm:py-28">
          <div className="mb-8 flex items-center gap-3 text-[10px] font-medium uppercase tracking-[0.35em] text-muted-foreground sm:mb-10 sm:text-xs">
            <span className="h-px w-8 bg-primary/60 sm:w-12" />
            <span>Strategic clarity, tuned in</span>
            <span className="h-px w-8 bg-primary/60 sm:w-12" />
          </div>
          <h1 className="max-w-4xl text-balance font-semibold text-4xl tracking-tight sm:text-6xl lg:text-7xl">
            A sharper view of the decisions that move your organization forward.
          </h1>
          <p className="mt-6 max-w-2xl text-balance text-base leading-7 text-muted-foreground sm:text-lg">
            Governance, compliance, and treasury intelligence brought into focus.
          </p>
          <div id="pricing" className="mt-10 flex flex-col items-center gap-3 sm:flex-row">
            <Button asChild size="lg" className="rounded-full px-5">
              <Link href="/dashboard">
                Enter workspace
                <ArrowRight data-icon="inline-end" aria-hidden="true" />
              </Link>
            </Button>
            <Button asChild size="lg" variant="outline" className="rounded-full px-5">
              <a href="#features">Explore services</a>
            </Button>
          </div>
        </section>

        <section id="features" className="mx-auto grid w-full max-w-6xl gap-3 border-y py-6 sm:grid-cols-3">
          {productLinks.map(({ title, description, icon: Icon }) => (
            <div key={title} className="flex items-start gap-3 px-3 py-2">
              <Icon className="mt-0.5 size-5 text-primary" aria-hidden="true" />
              <div>
                <h2 className="text-sm font-medium">{title}</h2>
                <p className="mt-1 text-sm leading-6 text-muted-foreground">{description}</p>
              </div>
            </div>
          ))}
        </section>
      </div>

      <Footer />
    </main>
  );
}
