"use client"

import * as React from "react"
import { ThumbsDown, ThumbsUp } from "lucide-react"
import { cn } from "cn"

export type PrismaReactionId = "like" | "dislike"

export function PrismaReactionBar({
  value,
  onChange,
  likeCount = 0,
  dislikeCount = 0,
  className,
  ariaLabel = "Реакция на материал",
}: {
  value?: PrismaReactionId
  onChange?: (reaction: PrismaReactionId) => void
  likeCount?: number
  dislikeCount?: number
  className?: string
  ariaLabel?: string
}) {
  const total = likeCount + dislikeCount
  const likeShare = total > 0 ? (likeCount / total) * 100 : 50
  const dislikeShare = 100 - likeShare

  return (
    <div className={cn("prisma-reaction-bar", className)} role="group" aria-label={ariaLabel}>
      <div className="prisma-reaction-stats">
        <button
          type="button"
          className={cn("prisma-reaction-item", value === "like" && "is-selected")}
          aria-label={`Нравится: ${likeCount}`}
          aria-pressed={value === "like"}
          onClick={() => onChange?.("like")}
        >
          <ThumbsUp aria-hidden="true" />
          <span>{likeCount}</span>
        </button>
        <button
          type="button"
          className={cn("prisma-reaction-item", value === "dislike" && "is-selected")}
          aria-label={`Не нравится: ${dislikeCount}`}
          aria-pressed={value === "dislike"}
          onClick={() => onChange?.("dislike")}
        >
          <ThumbsDown aria-hidden="true" />
          <span>{dislikeCount}</span>
        </button>
      </div>
      <div
        className="prisma-reaction-ratio"
        role="img"
        aria-label={`Нравится ${Math.round(likeShare)} процентов, не нравится ${Math.round(dislikeShare)} процентов`}
      >
        <span style={{ width: `${likeShare}%` }} />
      </div>
    </div>
  )
}
