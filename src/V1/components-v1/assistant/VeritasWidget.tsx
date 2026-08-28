"use client";

import { useState } from "react";
import { usePathname } from "next/navigation";
import { Column, IconButton } from "@once-ui-system/core";
import { AssistantChat } from "./AssistantChat";

/** Global floating toggle: Veritas is reachable from every /app/* page, not just its own. */
export function VeritasWidget() {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();

  if (pathname === "/app/assistant") return null;

  return (
    <>
      {!open && (
        <IconButton
          icon="sparkle"
          size="l"
          variant="primary"
          tooltip="Ask Veritas"
          tooltipPosition="left"
          onClick={() => setOpen(true)}
          style={{ position: "fixed", right: "24px", bottom: "24px", zIndex: 40, boxShadow: "0 4px 16px rgba(0,0,0,0.3)" }}
        />
      )}
      {open && (
        <Column
          background="surface"
          border="neutral-alpha-medium"
          radius="l"
          shadow="l"
          padding="16"
          style={{
            position: "fixed",
            right: "24px",
            bottom: "24px",
            top: "24px",
            width: "420px",
            maxWidth: "calc(100vw - 48px)",
            zIndex: 40,
          }}
        >
          <AssistantChat onClose={() => setOpen(false)} />
        </Column>
      )}
    </>
  );
}
