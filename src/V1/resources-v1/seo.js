// Canonical production origin.
const baseURL = "https://app.intune.dev";

// metadata for pages
const meta = {
  home: {
    path: "/",
    title: "Forens_iQ — Evidence-Grade Case Management",
    description:
      "A defensible, evidence-native platform for fraud examination, forensic accounting, treasury governance, litigation support, and court/monitor engagements.",
    image: "/images/og/home.jpg",
    canonical: "https://app.intune.dev",
    robots: "index,follow",
    alternates: [{ href: "https://app.intune.dev", hrefLang: "en" }],
  },
  // add more routes and reference them in page.tsx
};

// default schema data
const schema = {
  logo: "",
  type: "Organization",
  name: "Forens_iQ",
  description: meta.home.description,
};

export { meta, schema, baseURL };
