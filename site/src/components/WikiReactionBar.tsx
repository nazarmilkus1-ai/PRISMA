"use client"

import * as React from "react"
import { PrismaReactionBar, type PrismaReactionId } from "@prisma-eco/ui"

type StoredReactions = {
  reaction?: PrismaReactionId
  likes: number
  dislikes: number
}

function getInitial(slug: string): StoredReactions {
  try {
    const raw = window.localStorage.getItem(`prisma-wiki-reaction:${slug}`)
    if (!raw) return { likes: 0, dislikes: 0 }
    const parsed = JSON.parse(raw) as Partial<StoredReactions>
    return {
      reaction: parsed.reaction === "like" || parsed.reaction === "dislike" ? parsed.reaction : undefined,
      likes: Number.isFinite(parsed.likes) ? Math.max(0, Number(parsed.likes)) : 0,
      dislikes: Number.isFinite(parsed.dislikes) ? Math.max(0, Number(parsed.dislikes)) : 0,
    }
  } catch {
    return { likes: 0, dislikes: 0 }
  }
}

export default function WikiReactionBar({ slug }: { slug: string }) {
  const [state, setState] = React.useState<StoredReactions>(() => getInitial(slug))

  React.useEffect(() => {
    window.localStorage.setItem(`prisma-wiki-reaction:${slug}`, JSON.stringify(state))
  }, [slug, state])

  function setReaction(next: PrismaReactionId) {
    setState((current) => {
      if (current.reaction === next) return current
      return {
        reaction: next,
        likes: current.likes + (next === "like" ? 1 : 0) - (current.reaction === "like" ? 1 : 0),
        dislikes: current.dislikes + (next === "dislike" ? 1 : 0) - (current.reaction === "dislike" ? 1 : 0),
      }
    })
  }

  return (
    <div className="mt-8 border-t border-border/70 pt-6">
      <div className="mb-3 text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
        Реакция на статью
      </div>
      <PrismaReactionBar
        value={state.reaction}
        likeCount={state.likes}
        dislikeCount={state.dislikes}
        onChange={setReaction}
      />
    </div>
  )
}
