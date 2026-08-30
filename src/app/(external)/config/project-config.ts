import packageJson from "../../package.json";

const currentYear = new Date().getFullYear();

export const PROJECT_CONFIG = {
  name: "In.Tune & Associates",
  description: "Strategic clarity for governance, compliance, and treasury.",
  version: packageJson.version,
  copyright: `© ${currentYear}, All Rights Reserved.`,
};
