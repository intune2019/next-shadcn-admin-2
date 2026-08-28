import { redirect } from "next/navigation";
import { Column, Heading, Text } from "@once-ui-system/core";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/shell/AppShell";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return (
      <Column fillWidth minHeight="100vh" center padding="l">
        <Column maxWidth="s" gap="8" horizontal="center" align="center">
          <Heading variant="heading-strong-l">Supabase isn&apos;t connected yet</Heading>
          <Text onBackground="neutral-weak" align="center">
            Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in web/.env.local
            to reach the app.
          </Text>
        </Column>
      </Column>
    );
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/sign-in");
  }

  return <AppShell>{children}</AppShell>;
}
