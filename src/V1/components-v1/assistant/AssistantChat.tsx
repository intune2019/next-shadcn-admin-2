"use client";

import { useRef, useState, type FormEvent } from "react";
import { Column, Row, Text, Textarea, Button, IconButton, Badge, Line } from "@once-ui-system/core";
import { useTenant } from "@/lib/tenant/TenantContext";

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export function AssistantChat({ onClose }: { onClose?: () => void }) {
  const { matterId } = useTenant();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!input.trim() || sending || !matterId) return;

    const next: ChatMessage[] = [...messages, { role: "user", content: input.trim() }];
    setMessages([...next, { role: "assistant", content: "" }]);
    setInput("");
    setSending(true);

    try {
      const res = await fetch("/api/assistant/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ matterId, messages: next }),
      });

      if (!res.ok || !res.body) {
        const errText = await res.text();
        setMessages((m) => {
          const copy = [...m];
          copy[copy.length - 1] = { role: "assistant", content: `Error: ${errText}` };
          return copy;
        });
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let acc = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        acc += decoder.decode(value, { stream: true });
        setMessages((m) => {
          const copy = [...m];
          copy[copy.length - 1] = { role: "assistant", content: acc };
          return copy;
        });
        scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
      }
    } finally {
      setSending(false);
    }
  }

  return (
    <Column fillWidth fillHeight gap="16">
      <Row horizontal="between" vertical="center">
        <Column gap="4">
          <Row gap="8" vertical="center">
            <Badge textVariant="code-default-s" border="neutral-alpha-medium" onBackground="neutral-medium">
              Veritas
            </Badge>
            <Text onBackground="neutral-weak">Intelligence &amp; legal cross-reference assistant</Text>
          </Row>
        </Column>
        {onClose && <IconButton icon="close" variant="tertiary" size="s" tooltip="Close" onClick={onClose} />}
      </Row>
      <Line />
      {!matterId && (
        <Text onBackground="danger-weak">Set an active matter (top bar) before talking to Veritas.</Text>
      )}
      <Column ref={scrollRef} fillWidth flex={1} overflowY="auto" gap="16" paddingY="8">
        {messages.length === 0 && (
          <Text onBackground="neutral-weak">
            Ask about the evidence, facts, findings, or allegations on this matter, or ask Veritas to
            cross-walk a finding against a legal framework or black-letter standard.
          </Text>
        )}
        {messages.map((m, i) => (
          <Column key={i} gap="4">
            <Text variant="label-default-s" onBackground="neutral-weak">
              {m.role === "user" ? "You" : "Veritas"}
            </Text>
            <Text style={{ whiteSpace: "pre-wrap" }}>{m.content || (sending && i === messages.length - 1 ? "…" : "")}</Text>
          </Column>
        ))}
      </Column>
      <Column as="form" onSubmit={handleSubmit} gap="8" fillWidth>
        <Textarea
          id="veritas-input"
          label="Ask Veritas"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              handleSubmit(e as unknown as FormEvent);
            }
          }}
        />
        <Row horizontal="end">
          <Button type="submit" loading={sending} disabled={!matterId} data-border="sharp">
            Send
          </Button>
        </Row>
      </Column>
    </Column>
  );
}
