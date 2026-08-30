import packageJson from "../../package.json";

const currentYear = new Date().getFullYear();

export const APP_CONFIG = {
  name: "H.E.O.S.",
  version: packageJson.version,
  copyright: `© ${currentYear}, H.E.O.S.`,
  meta: {
    title: "H.E.O.S. - Healthcare Operating System",
    description:
      "H.E.O.S. is the connected operating system for multi-practice healthcare teams, bringing patient care, operations, and revenue workflows into one workspace.",
  },
};
