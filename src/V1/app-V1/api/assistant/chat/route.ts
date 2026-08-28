import { createClaudeClient, CLAUDE_MODEL } from "@/lib/claude/client";
import { buildMatterTools } from "@/lib/claude/tools";
import { VERITAS_SYSTEM_PROMPT } from "@/lib/claude/system-prompt";
import { createClient as createServerClient } from "@/lib/supabase/server";
import type Anthropic from "@anthropic-ai/sdk";

export const runtime = "nodejs";

const MAX_ITERATIONS = 8;

export async function POST(req: Request) {
  if (!process.env.ANTHROPIC_API_KEY && !process.env.OPENAI_API_KEY) {
    return new Response("Veritas is not configured on this server.", { status: 503 });
  }

  const { matterId, messages } = (await req.json()) as {
    matterId?: string;
    messages: { role: "user" | "assistant"; content: string }[];
  };

  if (!matterId) {
    return new Response("Set an active matter before talking to Veritas.", { status: 400 });
  }

  const supabase = await createServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return new Response("Not signed in.", { status: 401 });

  const { data: matter } = await supabase
    .schema("core")
    .from("matters")
    .select("id, matter_number, matter_name")
    .eq("id", matterId)
    .single();
  if (!matter) return new Response("No access to that matter.", { status: 403 });

  const claude = createClaudeClient();
  const { definitions: tools, execute } = buildMatterTools(supabase, matterId);

  const conversation: Anthropic.MessageParam[] = messages.map((m) => ({
    role: m.role,
    content: m.content,
  }));
  // First turn only: ground the model in which matter it's looking at without
  // baking a per-request value into the (cacheable) system prompt.
  if (conversation.length > 0 && conversation[0].role === "user") {
    conversation[0] = {
      role: "user",
      content: `[Active matter: ${matter.matter_number} — ${matter.matter_name}]\n\n${conversation[0].content}`,
    };
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      try {
        for (let i = 0; i < MAX_ITERATIONS; i++) {
          const messageStream = claude.messages.stream({
            model: CLAUDE_MODEL,
            max_tokens: 4096,
            thinking: { type: "adaptive" },
            output_config: { effort: "high" },
            system: [{ type: "text", text: VERITAS_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
            tools,
            messages: conversation,
          });

          for await (const event of messageStream) {
            if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
              controller.enqueue(encoder.encode(event.delta.text));
            }
          }

          const final = await messageStream.finalMessage();
          conversation.push({ role: "assistant", content: final.content });

          if (final.stop_reason !== "tool_use") break;

          const toolUses = final.content.filter(
            (b): b is Anthropic.ToolUseBlock => b.type === "tool_use",
          );
          const results: Anthropic.ToolResultBlockParam[] = [];
          for (const use of toolUses) {
            const output = await execute(use.name, use.input as Record<string, unknown>);
            results.push({ type: "tool_result", tool_use_id: use.id, content: output });
          }
          conversation.push({ role: "user", content: results });
        }
      } catch (err) {
        controller.enqueue(encoder.encode(`\n\n[Veritas error: ${(err as Error).message}]`));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
