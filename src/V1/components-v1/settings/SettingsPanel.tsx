"use client";

import { useEffect, useState, type FormEvent } from "react";
import { Column, Row, Heading, Text, Input, Button, Line, useToast } from "@once-ui-system/core";
import { createClient } from "@/lib/supabase/client";
import { useTenant } from "@/lib/tenant/TenantContext";

export function SettingsPanel() {
  const { addToast } = useToast();
  const { tenantId, matterId } = useTenant();
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    async function load() {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) {
        setLoading(false);
        return;
      }
      setEmail(user.email ?? "");
      const { data: profile } = await supabase
        .schema("core")
        .from("profiles")
        .select("display_name")
        .eq("id", user.id)
        .single();
      setDisplayName((profile?.display_name as string) ?? "");
      setLoading(false);
    }
    load();
  }, []);

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      setSaving(false);
      return;
    }
    const { error } = await supabase.schema("core").from("profiles").update({ display_name: displayName }).eq("id", user.id);
    setSaving(false);
    if (error) {
      addToast({ variant: "danger", message: error.message });
      return;
    }
    addToast({ variant: "success", message: "Profile updated." });
  }

  return (
    <Column fillWidth gap="32" maxWidth="s">
      <Column gap="4">
        <Heading variant="heading-strong-l">Settings</Heading>
        <Text onBackground="neutral-weak">Your profile and this workspace&apos;s active context.</Text>
      </Column>

      <Column as="form" onSubmit={handleSave} gap="16" fillWidth>
        <Heading variant="heading-strong-s">Your profile</Heading>
        <Input id="settings-email" label="Email" value={email} disabled readOnly />
        <Input
          id="settings-display-name"
          label="Display name"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
        />
        <Row horizontal="end">
          <Button type="submit" loading={loading || saving} data-border="sharp">
            Save
          </Button>
        </Row>
      </Column>

      <Line />

      <Column gap="16" fillWidth>
        <Heading variant="heading-strong-s">Workspace</Heading>
        <Row fillWidth horizontal="between">
          <Text onBackground="neutral-weak">Active tenant</Text>
          <Text>{tenantId ?? "not set"}</Text>
        </Row>
        <Row fillWidth horizontal="between">
          <Text onBackground="neutral-weak">Active matter</Text>
          <Text>{matterId ?? "not set"}</Text>
        </Row>
        <Text onBackground="neutral-weak">Change these from the top bar. They're stored locally to this browser.</Text>
      </Column>
    </Column>
  );
}
