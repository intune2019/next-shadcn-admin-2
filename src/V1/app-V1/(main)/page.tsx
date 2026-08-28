import {
  Heading,
  Text,
  Button,
  Column,
  Badge,
  LetterFx,
} from "@once-ui-system/core";
import { Schema } from "@once-ui-system/core";
import { baseURL, meta } from "@/resources/seo";

export default function Home() {
  return (
    <Column fillWidth minHeight="100vh" center padding="l">
      <Schema
        as="webPage"
        baseURL={baseURL}
        title={meta.home.title}
        description={meta.home.description}
        path={meta.home.path}
      />
      <Column maxWidth="s" horizontal="center" gap="l" align="center">
        <Badge
          textVariant="code-default-s"
          border="neutral-alpha-medium"
          onBackground="neutral-medium"
          vertical="center"
          gap="16"
        >
          <Text marginX="4">
            <LetterFx trigger="instant">Evidence-grade case management</LetterFx>
          </Text>
        </Badge>
        <Heading variant="display-strong-xl" marginTop="24">
          Every finding, traceable to its evidence
        </Heading>
        <Text
          variant="heading-default-xl"
          onBackground="neutral-weak"
          wrap="balance"
          marginBottom="16"
        >
          Forens_iQ turns raw financial and operational evidence into an
          auditable case file — from intake to court-ready report.
        </Text>
        <Button id="matters" href="/app/matters" data-border="sharp" arrowIcon>
          Enter Matter Command Center
        </Button>
      </Column>
    </Column>
  );
}
