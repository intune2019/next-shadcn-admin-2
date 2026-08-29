"use client";

import { useState } from "react";
import React from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown } from "lucide-react";

type Props = {
  navItems: {
    id: number;
    label: string;
    subMenus?: {
      title: string;
      items: {
        label: string;
        description: string;
        icon: React.ElementType;
      }[];
    }[];
    link?: string;
  }[];
};

export function DropdownNavigation({ navItems }: Props) {
  const [openMenu, setOpenMenu] = React.useState<string | null>(null);

  const handleHover = (menuLabel: string | null) => {
    setOpenMenu(menuLabel);
  };

  const [isHover, setIsHover] = useState<number | null>(null);

  return (
    <main className="relative flex min-h-screen w-full items-start justify-center px-4 py-10 md:items-center">
      <div className="relative flex flex-col items-center justify-center gap-5">
        <ul className="relative flex items-center space-x-0">
          {navItems.map((navItem) => (
            <li
              key={navItem.label}
              className="relative"
              onMouseEnter={() => handleHover(navItem.label)}
              onMouseLeave={() => handleHover(null)}
            >
              <button
                className="group relative flex cursor-pointer items-center justify-center gap-1 px-4 py-1.5 text-sm text-muted-foreground transition-colors duration-300 hover:text-foreground"
                onMouseEnter={() => setIsHover(navItem.id)}
                onMouseLeave={() => setIsHover(null)}
              >
                <span>{navItem.label}</span>
                {navItem.subMenus && (
                  <ChevronDown
                    className={`h-4 w-4 transition-transform duration-300 group-hover:rotate-180 ${
                      openMenu === navItem.label ? "rotate-180" : ""
                    }`}
                  />
                )}
                {(isHover === navItem.id || openMenu === navItem.label) && (
                  <motion.div
                    layoutId="hover-bg"
                    className="absolute inset-0 size-full bg-primary/10"
                    style={{ borderRadius: 99 }}
                  />
                )}
              </button>

              <AnimatePresence>
                {openMenu === navItem.label && navItem.subMenus && (
                  <div className="absolute left-0 top-full w-auto pt-2">
                    <motion.div
                      className="w-max border border-border bg-background p-4"
                      style={{ borderRadius: 16 }}
                      layoutId="menu"
                    >
                      <div className="flex w-fit shrink-0 space-x-9 overflow-hidden">
                        {navItem.subMenus.map((sub) => (
                          <motion.div layout className="w-full" key={sub.title}>
                            <h3 className="mb-4 text-sm font-medium capitalize text-muted-foreground">
                              {sub.title}
                            </h3>
                            <ul className="space-y-6">
                              {sub.items.map((item) => {
                                const Icon = item.icon;
                                return (
                                  <li key={item.label}>
                                    <a href="#" className="group flex items-start space-x-3">
                                      <div className="flex size-9 shrink-0 items-center justify-center rounded-md border border-border text-foreground transition-colors duration-300 group-hover:bg-accent group-hover:text-accent-foreground">
                                        <Icon className="h-5 w-5 flex-none" />
                                      </div>
                                      <div className="w-max leading-5">
                                        <p className="shrink-0 text-sm font-medium text-foreground">
                                          {item.label}
                                        </p>
                                        <p className="shrink-0 text-xs text-muted-foreground transition-colors duration-300 group-hover:text-foreground">
                                          {item.description}
                                        </p>
                                      </div>
                                    </a>
                                  </li>
                                );
                              })}
                            </ul>
                          </motion.div>
                        ))}
                      </div>
                    </motion.div>
                  </div>
                )}
              </AnimatePresence>
            </li>
          ))}
        </ul>
      </div>
    </main>
  );
}
