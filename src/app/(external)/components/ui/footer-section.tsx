import type { ComponentType } from "react";

import { FacebookIcon, FrameIcon, InstagramIcon, LinkedinIcon, YoutubeIcon } from "lucide-react";

interface FooterLink {
  title: string;
  href: string;
  icon?: ComponentType<{ className?: string }>;
}

interface FooterSection {
  label: string;
  links: FooterLink[];
}

const footerLinks: FooterSection[] = [
  {
    label: "Product",
    links: [
      { title: "Features", href: "#features" },
      { title: "Pricing", href: "#pricing" },
      { title: "Testimonials", href: "#testimonials" },
      { title: "Integration", href: "/" },
    ],
  },
  {
    label: "Company",
    links: [
      { title: "FAQs", href: "/faqs" },
      { title: "About Us", href: "/about" },
      { title: "Privacy Policy", href: "/privacy" },
      { title: "Terms of Services", href: "/terms" },
    ],
  },
  {
    label: "Resources",
    links: [
      { title: "Blog", href: "/blog" },
      { title: "Changelog", href: "/changelog" },
      { title: "Brand", href: "/brand" },
      { title: "Help", href: "/help" },
    ],
  },
  {
    label: "Social Links",
    links: [
      { title: "Facebook", href: "#", icon: FacebookIcon },
      { title: "Instagram", href: "#", icon: InstagramIcon },
      { title: "Youtube", href: "#", icon: YoutubeIcon },
      { title: "LinkedIn", href: "#", icon: LinkedinIcon },
    ],
  },
];

export function Footer() {
  return (
    <footer className="relative mx-auto flex w-full max-w-6xl flex-col items-center justify-center rounded-t-[2rem] border-t bg-[radial-gradient(35%_128px_at_50%_0%,rgba(242,242,242,0.08),transparent)] px-6 py-12 md:rounded-t-[3rem] lg:py-16">
      <div className="absolute top-0 right-1/2 left-1/2 h-px w-1/3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-foreground/20 blur" />

      <div className="grid w-full gap-8 xl:grid-cols-3 xl:gap-8">
        <div className="space-y-4">
          <FrameIcon className="size-8" />
          <p className="mt-8 text-sm text-muted-foreground md:mt-0">
            © {new Date().getFullYear()} In.Tune &amp; Associates. All rights reserved.
          </p>
        </div>

        <div className="mt-10 grid grid-cols-2 gap-8 md:grid-cols-4 xl:col-span-2 xl:mt-0">
          {footerLinks.map((section) => (
            <div key={section.label} className="mb-10 md:mb-0">
              <h3 className="text-xs">{section.label}</h3>
              <ul className="mt-4 space-y-2 text-sm text-muted-foreground">
                {section.links.map((link) => (
                  <li key={link.title}>
                    <a href={link.href} className="inline-flex items-center transition-colors duration-300 hover:text-foreground">
                      {link.icon && <link.icon className="me-1 size-4" />}
                      {link.title}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </footer>
  );
}
