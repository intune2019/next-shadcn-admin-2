"use client";

import { createMatterIntake } from "@/app/app/matters/actions";
import { useTenant } from "@/lib/tenant/TenantContext";
import {
  Badge,
  Button,
  Card,
  Checkbox,
  Column,
  Heading,
  Input,
  Line,
  Row,
  Select,
  Text,
  Textarea,
  useToast,
} from "@once-ui-system/core";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";

const MODULES = [
  ["fraud_examination", "Fraud examination"],
  ["treasury", "Treasury / cash governance"],
  ["grc_audit", "GRC / compliance / audit"],
  ["litigation", "Litigation and damages"],
  ["court_receivership", "Court / monitor / receivership"],
  ["claims", "Claims administration"],
] as const;

const STEPS = ["Matter", "Services & parties", "Authority", "Governance"];

export function MatterIntakeWizard() {
  const router = useRouter();
  const { addToast } = useToast();
  const { tenantId, setMatterId } = useTenant();
  const [step, setStep] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const [values, setValues] = useState({
    matterName: "",
    matterType: "fraud_examination",
    jurisdiction: "",
    confidentiality: "attorney_work_product",
    riskLevel: "standard",
    modules: ["fraud_examination"] as string[],
    partyName: "",
    partyRole: "client",
    counsel: "",
    authorityType: "engagement_letter",
    issuingParty: "",
    effectiveDate: "",
    expirationDate: "",
    mandate: "",
    deadlineType: "initial_report",
    dueAt: "",
    conflictAttestation:
      "I have reviewed known parties and relationships and disclosed any actual or potential conflict.",
    conflictIdentified: false,
    retentionCategory: "matter_standard",
  });

  function setField<K extends keyof typeof values>(key: K, value: (typeof values)[K]) {
    setValues((current) => ({ ...current, [key]: value }));
  }

  function toggleModule(module: string) {
    setValues((current) => ({
      ...current,
      modules: current.modules.includes(module)
        ? current.modules.filter((item) => item !== module)
        : [...current.modules, module],
    }));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (step < STEPS.length - 1) {
      if (step === 0 && !values.matterName.trim()) {
        addToast({ variant: "danger", message: "Matter name is required." });
        return;
      }
      if (step === 1 && !values.modules.length) {
        addToast({ variant: "danger", message: "Select at least one service module." });
        return;
      }
      setStep((current) => current + 1);
      return;
    }
    if (!tenantId) {
      addToast({ variant: "danger", message: "Set an active tenant in the top bar first." });
      return;
    }
    setSubmitting(true);
    const result = await createMatterIntake({
      tenantId,
      matterName: values.matterName,
      matterType: values.matterType,
      jurisdiction: values.jurisdiction,
      confidentiality: values.confidentiality,
      riskLevel: values.riskLevel,
      modules: values.modules,
      parties: values.partyName.trim()
        ? [{ party_name: values.partyName, party_role: values.partyRole, counsel: values.counsel }]
        : [],
      authority: {
        authority_type: values.authorityType,
        issuing_party: values.issuingParty,
        effective_date: values.effectiveDate,
        expiration_date: values.expirationDate,
        mandate: values.mandate,
      },
      deadlines: values.dueAt ? [{ deadline_type: values.deadlineType, due_at: values.dueAt }] : [],
      conflictAttestation: values.conflictAttestation,
      conflictIdentified: values.conflictIdentified,
      retentionCategory: values.retentionCategory,
    });
    setSubmitting(false);
    if ("error" in result) {
      addToast({ variant: "danger", message: result.error });
      return;
    }
    setMatterId(result.id);
    addToast({
      variant: "success",
      message: `Matter ${result.matterNumber} created for scope review.`,
    });
    router.push(`/app/matters/${result.id}/authority`);
  }

  return (
    <Column as="form" onSubmit={submit} fillWidth gap="24">
      <Column gap="8">
        <Row gap="8" wrap>
          {STEPS.map((label, index) => (
            <Badge key={label} onBackground={index === step ? "brand-strong" : "neutral-weak"}>
              {index + 1}. {label}
            </Badge>
          ))}
        </Row>
        <Heading variant="heading-strong-l">New matter intake</Heading>
        <Text onBackground="neutral-weak">
          Establish the engagement, authority, scope inputs, access posture, and reporting
          obligations before analysis begins.
        </Text>
      </Column>
      <Line />

      {step === 0 && (
        <Column gap="16">
          <Input
            id="matter-name"
            label="Client and matter name"
            required
            value={values.matterName}
            onChange={(e) => setField("matterName", e.target.value)}
          />
          <Row gap="16" wrap>
            <Select
              id="matter-type"
              label="Engagement type"
              value={values.matterType}
              onSelect={(v) => setField("matterType", v as string)}
              options={MODULES.map(([value, label]) => ({ value, label }))}
            />
            <Input
              id="jurisdiction"
              label="Jurisdiction"
              value={values.jurisdiction}
              onChange={(e) => setField("jurisdiction", e.target.value)}
            />
          </Row>
          <Row gap="16" wrap>
            <Select
              id="risk-level"
              label="Risk level"
              value={values.riskLevel}
              onSelect={(v) => setField("riskLevel", v as string)}
              options={["low", "standard", "high", "critical"].map((value) => ({
                value,
                label: value,
              }))}
            />
            <Select
              id="confidentiality"
              label="Confidentiality"
              value={values.confidentiality}
              onSelect={(v) => setField("confidentiality", v as string)}
              options={[
                "internal",
                "client_confidential",
                "attorney_client_privileged",
                "attorney_work_product",
                "highly_restricted",
                "court_sealed",
                "regulatory_restricted",
              ].map((value) => ({ value, label: value.replaceAll("_", " ") }))}
            />
          </Row>
        </Column>
      )}

      {step === 1 && (
        <Column gap="20">
          <Column gap="8">
            <Heading variant="heading-strong-s">Service modules</Heading>
            <Row gap="12" wrap>
              {MODULES.map(([value, label]) => (
                <Card key={value} padding="16" border="neutral-alpha-medium">
                  <Checkbox
                    id={`module-${value}`}
                    label={label}
                    isChecked={values.modules.includes(value)}
                    onToggle={() => toggleModule(value)}
                  />
                </Card>
              ))}
            </Row>
          </Column>
          <Line />
          <Heading variant="heading-strong-s">Primary party</Heading>
          <Input
            id="party-name"
            label="Party or entity name"
            value={values.partyName}
            onChange={(e) => setField("partyName", e.target.value)}
          />
          <Row gap="16" wrap>
            <Select
              id="party-role"
              label="Role"
              value={values.partyRole}
              onSelect={(v) => setField("partyRole", v as string)}
              options={[
                "client",
                "subject",
                "opposing",
                "court",
                "regulator",
                "witness",
                "other",
              ].map((value) => ({ value, label: value }))}
            />
            <Input
              id="party-counsel"
              label="Counsel"
              value={values.counsel}
              onChange={(e) => setField("counsel", e.target.value)}
            />
          </Row>
        </Column>
      )}

      {step === 2 && (
        <Column gap="16">
          <Row gap="16" wrap>
            <Select
              id="authority-type"
              label="Authority instrument"
              value={values.authorityType}
              onSelect={(v) => setField("authorityType", v as string)}
              options={[
                "engagement_letter",
                "court_order",
                "subpoena",
                "consent_decree",
                "appointment_order",
                "other",
              ].map((value) => ({ value, label: value.replaceAll("_", " ") }))}
            />
            <Input
              id="issuing-party"
              label="Issuing party"
              value={values.issuingParty}
              onChange={(e) => setField("issuingParty", e.target.value)}
            />
          </Row>
          <Row gap="16" wrap>
            <Input
              id="effective-date"
              type="date"
              label="Effective date"
              value={values.effectiveDate}
              onChange={(e) => setField("effectiveDate", e.target.value)}
            />
            <Input
              id="expiration-date"
              type="date"
              label="Expiration date"
              value={values.expirationDate}
              onChange={(e) => setField("expirationDate", e.target.value)}
            />
          </Row>
          <Textarea
            id="mandate"
            label="Mandate, duties, restrictions, and reporting clauses"
            lines={9}
            value={values.mandate}
            onChange={(e) => setField("mandate", e.target.value)}
            description="Use one clause per line. The authority parser will propose structured scope items for professional review."
          />
          <Row gap="16" wrap>
            <Input
              id="deadline-type"
              label="Initial deadline type"
              value={values.deadlineType}
              onChange={(e) => setField("deadlineType", e.target.value)}
            />
            <Input
              id="deadline"
              type="datetime-local"
              label="Initial deadline"
              value={values.dueAt}
              onChange={(e) => setField("dueAt", e.target.value)}
            />
          </Row>
        </Column>
      )}

      {step === 3 && (
        <Column gap="16">
          <Select
            id="retention"
            label="Retention category"
            value={values.retentionCategory}
            onSelect={(v) => setField("retentionCategory", v as string)}
            options={[
              { value: "matter_standard", label: "Matter standard" },
              { value: "court_controlled", label: "Court controlled" },
              { value: "regulatory_hold", label: "Regulatory hold" },
            ]}
          />
          <Textarea
            id="conflict-attestation"
            label="Conflict and independence attestation"
            required
            lines={5}
            value={values.conflictAttestation}
            onChange={(e) => setField("conflictAttestation", e.target.value)}
          />
          <Checkbox
            id="conflict-identified"
            label="An actual or potential conflict was identified"
            isChecked={values.conflictIdentified}
            onToggle={() => setField("conflictIdentified", !values.conflictIdentified)}
          />
          <Card padding="16" border="neutral-alpha-medium">
            <Text variant="body-default-s">
              Creating this intake preserves the attestation and opens Authority and Scope Review.
              Analytics remain gated until a user with approval authority confirms the extracted
              scope.
            </Text>
          </Card>
        </Column>
      )}

      <Row horizontal="between" gap="12">
        <Button
          type="button"
          variant="secondary"
          disabled={step === 0 || submitting}
          onClick={() => setStep((current) => current - 1)}
        >
          Back
        </Button>
        <Button type="submit" loading={submitting}>
          {step === STEPS.length - 1 ? "Create intake" : "Continue"}
        </Button>
      </Row>
    </Column>
  );
}
