import { isPublicModuleEnabled } from "@/lib/modules";
import { NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PARTICIPANT_POLL_MUTATION_RPC } from "@prisma-eco/contracts";

async function moduleDisabledResponse(request: Request) {
  return NextResponse.redirect(new URL("/app?error=module_disabled&module=voting", request.url), 303);
}

export async function POST(request: Request) {
  if (!(await isPublicModuleEnabled("voting"))) return moduleDisabledResponse(request);
  const user = await requireUser();
  if (user.status !== "ACCEPTED" || user.is_banned) {
    return NextResponse.redirect(new URL("/app/voting?error=forbidden", request.url), 303);
  }

  const form = await request.formData();
  const pollId = String(form.get("poll_id") || "");
  const optionIds = form.getAll("option_id").map(String).filter(Boolean);

  if (!pollId || !optionIds.length || optionIds.length > 20) {
    return NextResponse.redirect(new URL("/app/voting?error=invalid", request.url), 303);
  }

  const db = await createSupabaseServerClient();
  const { error } = await db.rpc(PARTICIPANT_POLL_MUTATION_RPC.voteMany, {
    p_poll_id: pollId,
    p_option_ids: optionIds,
  });

  if (error) {
    console.error("[site/voting]", error);
    const code = error.message === "MAX_CHOICES_REACHED"
      ? "max_choices"
      : error.message === "CANNOT_CHANGE_VOTE"
        ? "cannot_change"
        : error.message === "MULTIPLE_OPTIONS_NOT_ALLOWED"
          ? "single_choice"
          : error.message === "POLL_EXPIRED"
            ? "expired"
            : "vote_failed";

    return NextResponse.redirect(
      new URL("/app/voting?error=" + code, request.url),
      303,
    );
  }

  return NextResponse.redirect(new URL("/app/voting?voted=1", request.url), 303);
}
