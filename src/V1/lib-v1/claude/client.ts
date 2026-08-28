import Anthropic from "@anthropic-ai/sdk";

export function createClaudeClient() {
  const apiKey = process.env.ANTHROPIC_API_KEY ?? process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("Veritas is not configured. Set ANTHROPIC_API_KEY or OPENAI_API_KEY.");
  }

  return new Anthropic({
    apiKey,
    baseURL: process.env.ANTHROPIC_BASE_URL ?? "https://api.anthropic.com",
  });
}

export const CLAUDE_MODEL = process.env.ANTHROPIC_MODEL ?? "claude-opus-4-8";
