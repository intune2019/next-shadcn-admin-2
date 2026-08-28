"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  Column,
  Heading,
  Text,
  Input,
  PasswordInput,
  Button,
  Badge,
  useToast,
} from "@once-ui-system/core";
import { createClient } from "@/lib/supabase/client";

export default function SignIn() {
  const router = useRouter();
  const { addToast } = useToast();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    const supabase = createClient();

    const { error } = await supabase.auth.signInWithPassword({ email, password });

    setLoading(false);

    if (error) {
      addToast({ variant: "danger", message: error.message });
      return;
    }

    router.push("/app/matters");
    router.refresh();
  }

  return (
    <Column fillWidth minHeight="100vh" center padding="l">
      <Column maxWidth="xs" fillWidth gap="l">
        <Column gap="8">
          <Badge textVariant="code-default-s" border="neutral-alpha-medium" onBackground="neutral-medium">
            Forens_iQ
          </Badge>
          <Heading variant="display-strong-s">
            Sign in
          </Heading>
          <Text onBackground="neutral-weak">
            Accounts are provisioned by an administrator. Matter access is
            granted by a matter admin.
          </Text>
        </Column>
        <Column as="form" onSubmit={handleSubmit} gap="16" fillWidth>
          <Input
            id="email"
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <PasswordInput
            id="password"
            label="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            minLength={6}
            required
          />
          <Button type="submit" fillWidth loading={loading} data-border="sharp">
            Sign in
          </Button>
        </Column>
      </Column>
    </Column>
  );
}
